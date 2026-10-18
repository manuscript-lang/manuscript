package msruntime

import (
	"bytes"
	"errors"
	"io"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
	"unicode/utf8"
)

// readBounded reads reader to its end, failing when more than max bytes
// arrive. The code names the failure: LimitExceeded, InvalidData, or Failed.
func readBounded(ctx *Execution, reader io.Reader, max int) ([]byte, string) {
	var out []byte
	const chunkSize = 32 * 1024
	// One spare byte detects an exceeded limit. Clamp before adding so an
	// unbounded MaxInt limit cannot overflow.
	buffer := make([]byte, min(max, chunkSize-1)+1)
	for {
		CheckCancelled(ctx)
		remaining := max - len(out)
		chunk := buffer
		if remaining < len(buffer) {
			chunk = buffer[:int(remaining)+1]
		}
		n, err := reader.Read(chunk)
		if int(n) > remaining {
			return nil, "LimitExceeded"
		}
		out = append(out, chunk[:n]...)
		if err == io.EOF {
			return out, ""
		}
		if err != nil {
			return nil, "InvalidData"
		}
		if n == 0 {
			return nil, "Failed"
		}
	}
}

// readAhead holds bytes a line reader took beyond the current line. The owner's
// mutex guards it.
type readAhead struct{ buf []byte }

// take removes up to max bytes (all of them when max <= 0), reporting whether
// any were held.
func (a *readAhead) take(max int) ([]byte, bool) {
	if len(a.buf) == 0 {
		return nil, false
	}
	n := len(a.buf)
	if max > 0 && max < n {
		n = max
	}
	data := a.buf[:n:n]
	a.buf = a.buf[n:]
	return data, true
}

// lineSource is implemented by streams that can hold read-ahead for ReadLine.
type lineSource interface {
	lineBuffer() (*sync.Mutex, *readAhead)
}

func ioFailure[T any](e IoError) Result[T, IoError] { return Fail[T, IoError](e) }

// hostStream is a synchronized ReadStream and WriteStream over an *os.File.
// Reads and writes are serialized separately; Close interrupts admitted I/O,
// releases the descriptor once, and joins the admitted calls.
type hostStream struct {
	mu                  sync.Mutex
	file                *os.File
	closed, owned       bool
	admitted            int
	readGate, writeGate chan struct{}
	closing, released   chan struct{}
	active              sync.WaitGroup
	releaseFault        error
	pending             readAhead
	pumpOnce            sync.Once
	pump                bool        // reads cannot be interrupted by a deadline
	inflight            *streamRead // the started read a cancelled call left running
}

// streamRead is one read of a descriptor that has no read deadlines, started
// on its own goroutine so a cancelled caller can leave it running.
type streamRead struct {
	buf  []byte
	n    int
	err  error
	done chan struct{}
}

var (
	_ ReadStream  = (*hostStream)(nil)
	_ WriteStream = (*hostStream)(nil)
	_ lineSource  = (*hostStream)(nil)
)

func newHostStream(file *os.File, owned bool) *hostStream {
	s := &hostStream{file: file, owned: owned, closing: make(chan struct{}), released: make(chan struct{}), readGate: make(chan struct{}, 1), writeGate: make(chan struct{}, 1)}
	s.readGate <- struct{}{}
	s.writeGate <- struct{}{}
	return s
}

func (s *hostStream) lineBuffer() (*sync.Mutex, *readAhead) { return &s.mu, &s.pending }

func (s *hostStream) Close(*Execution) Unit {
	s.mu.Lock()
	if s.closed {
		released := s.released
		s.mu.Unlock()
		<-released
		if s.releaseFault != nil {
			Raise(s.releaseFault.Error())
		}
		return Unit{}
	}
	s.closed = true
	close(s.closing)
	active := s.admitted
	s.mu.Unlock()
	if active > 0 {
		s.file.SetReadDeadline(time.Now())
		s.file.SetWriteDeadline(time.Now())
	}
	if s.owned {
		s.releaseFault = s.file.Close()
	}
	s.active.Wait()
	close(s.released)
	if s.releaseFault != nil {
		Raise(s.releaseFault.Error())
	}
	return Unit{}
}

// admit waits for the read or write gate and registers the call. It returns
// ok false when the stream is closed.
func (s *hostStream) admit(ctx *Execution, write bool) (release func(), ok bool) {
	s.mu.Lock()
	gate := s.readGate
	if write {
		gate = s.writeGate
	}
	closing, closed := s.closing, s.closed
	s.mu.Unlock()
	if closed {
		return nil, false
	}
	select {
	case <-gate:
	case <-closing:
		return nil, false
	case <-ctx.Context.Done():
		CheckCancelled(ctx)
	}
	s.mu.Lock()
	if s.closed {
		s.mu.Unlock()
		gate <- struct{}{}
		return nil, false
	}
	s.active.Add(1)
	s.admitted++
	s.mu.Unlock()
	return func() {
		s.mu.Lock()
		s.admitted--
		s.mu.Unlock()
		s.active.Done()
		gate <- struct{}{}
	}, true
}

func (s *hostStream) isClosed() bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.closed
}

func (s *hostStream) Read(ctx *Execution, maxBytes Option[int]) Result[Option[*Bytes], IoError] {
	release, ok := s.admit(ctx, false)
	if !ok {
		return ioFailure[Option[*Bytes]](IoError_Closed{})
	}
	defer release()
	CheckCancelled(ctx)
	defer interruptDeadline(ctx, s.file.SetReadDeadline)()
	n := 65536
	if maxBytes.Some {
		if maxBytes.Val < 0 {
			return ioFailure[Option[*Bytes]](IoError_InvalidInput{})
		}
		n = maxBytes.Val
	}
	if n <= 0 {
		return ioFailure[Option[*Bytes]](IoError_InvalidInput{})
	}
	if n > 64*1024 {
		n = 64 * 1024
	}
	s.mu.Lock()
	data, held := s.pending.take(int(n))
	s.mu.Unlock()
	if held {
		return Ok[Option[*Bytes], IoError](Some(NewBytes(data)))
	}
	data = make([]byte, int(n))
	read, err := s.readFile(ctx, data)
	CheckCancelled(ctx)
	if err != nil && err != io.EOF {
		if s.isClosed() {
			return ioFailure[Option[*Bytes]](IoError_Closed{})
		}
		return ioFailure[Option[*Bytes]](IoError_Failed{Message: err.Error()})
	}
	if read == 0 && err == io.EOF {
		return Ok[Option[*Bytes], IoError](None[*Bytes]())
	}
	return Ok[Option[*Bytes], IoError](Some(NewBytes(data[:read])))
}

// readFile reads from the descriptor. Pipes and terminals inherited as blocking
// descriptors (the usual standard input) ignore read deadlines, so cancellation
// and Close could never interrupt them. Those reads run on their own goroutine;
// a cancelled call returns while the read stays pending, and the next Read
// takes its bytes so none are lost.
func (s *hostStream) readFile(ctx *Execution, data []byte) (int, error) {
	s.pumpOnce.Do(func() {
		if info, err := s.file.Stat(); err == nil && info.Mode().IsRegular() {
			return
		}
		s.pump = errors.Is(s.file.SetReadDeadline(time.Time{}), os.ErrNoDeadline)
	})
	if !s.pump {
		return s.file.Read(data)
	}
	s.mu.Lock()
	read := s.inflight
	if read == nil {
		read = &streamRead{buf: make([]byte, len(data)), done: make(chan struct{})}
		s.inflight = read
		go func() {
			read.n, read.err = s.file.Read(read.buf)
			close(read.done)
		}()
	}
	closing := s.closing
	s.mu.Unlock()
	select {
	case <-read.done:
	case <-ctx.Context.Done():
		CheckCancelled(ctx)
	case <-closing:
		return 0, os.ErrClosed
	}
	s.mu.Lock()
	s.inflight = nil
	n := copy(data, read.buf[:read.n])
	if n < read.n {
		s.pending.buf = append(s.pending.buf, read.buf[n:read.n]...)
	}
	s.mu.Unlock()
	return n, read.err
}

func (s *hostStream) Write(ctx *Execution, data *Bytes) Result[Unit, IoError] {
	release, ok := s.admit(ctx, true)
	if !ok {
		return ioFailure[Unit](IoError_Closed{})
	}
	defer release()
	CheckCancelled(ctx)
	defer interruptDeadline(ctx, s.file.SetWriteDeadline)()
	rest := data.Data
	for len(rest) > 0 {
		n, err := s.file.Write(rest)
		CheckCancelled(ctx)
		if err != nil {
			if s.isClosed() {
				return ioFailure[Unit](IoError_Closed{})
			}
			return ioFailure[Unit](IoError_Failed{Message: err.Error()})
		}
		if n == 0 {
			return ioFailure[Unit](IoError_Failed{Message: "short write"})
		}
		rest = rest[n:]
	}
	return Ok[Unit, IoError](Unit{})
}

func (s *hostStream) Flush(ctx *Execution) Result[Unit, IoError] {
	release, ok := s.admit(ctx, true)
	if !ok {
		return ioFailure[Unit](IoError_Closed{})
	}
	defer release()
	CheckCancelled(ctx)
	return Ok[Unit, IoError](Unit{})
}

// osFiles opens read-only file resources.
type osFiles struct{ directory string }

var _ Files = (*osFiles)(nil)

func (f *osFiles) Open(ctx *Execution, name string) Result[File, IoError] {
	CheckCancelled(ctx)
	if strings.ContainsRune(name, 0) {
		return ioFailure[File](IoError_InvalidInput{})
	}
	if !filepath.IsAbs(name) {
		var ok bool
		name, ok = hostPath(f.directory, name)
		if !ok {
			return ioFailure[File](IoError_Unavailable{})
		}
	}
	file, err := os.Open(name)
	if err != nil {
		return ioFailure[File](IoError_Unavailable{})
	}
	resource := newHostStream(file, true)
	if ctx.Context.Err() != nil {
		file.Close()
		CheckCancelled(ctx)
	}
	return Ok[File, IoError](resource)
}

var _ File = (*hostStream)(nil)

// Io_Copy copies bytes until end of input or the byte limit; it returns the
// number copied.
func Io_Copy(ctx *Execution, input ReadStream, output WriteStream, maxBytes Option[int]) Result[int, IoError] {
	max, ok := optionLimit(maxBytes, unlimited)
	if !ok {
		return ioFailure[int](IoError_InvalidInput{})
	}
	total := 0
	for {
		CheckCancelled(ctx)
		n := 32768
		if max-total < n {
			n = max - total + 1
		}
		value := input.Read(ctx, Some(n))
		if value.Failed {
			return Fail[int](value.Err)
		}
		if !value.Val.Some {
			return Ok[int, IoError](total)
		}
		data := value.Val.Val
		if len(data.Data) == 0 || len(data.Data) > n {
			return ioFailure[int](IoError_Failed{Message: "invalid stream chunk"})
		}
		if len(data.Data) > max-total {
			return ioFailure[int](IoError_LimitExceeded{})
		}
		if written := output.Write(ctx, data); written.Failed {
			return Fail[int](written.Err)
		}
		total += len(data.Data)
	}
}

// Io_ReadAll reads a stream completely into memory.
func Io_ReadAll(ctx *Execution, input ReadStream, maxBytes Option[int]) Result[*Bytes, IoError] {
	max, ok := optionLimit(maxBytes, unlimited)
	if !ok {
		return ioFailure[*Bytes](IoError_InvalidInput{})
	}
	var out []byte
	for {
		n := 32768
		if max-len(out) < n {
			n = max - len(out) + 1
		}
		value := input.Read(ctx, Some(n))
		if value.Failed {
			return Fail[*Bytes](value.Err)
		}
		if !value.Val.Some {
			return Ok[*Bytes, IoError](NewBytes(out))
		}
		data := value.Val.Val.Data
		if len(data) == 0 || len(data) > n {
			return ioFailure[*Bytes](IoError_Failed{Message: "invalid stream chunk"})
		}
		if len(data) > max-len(out) {
			return ioFailure[*Bytes](IoError_LimitExceeded{})
		}
		out = append(out, data...)
	}
}

// Io_ReadLine reads one line, omitting its line ending; none at end of stream.
func Io_ReadLine(ctx *Execution, input ReadStream, maxBytes Option[int]) Result[Option[string], IoError] {
	max, ok := optionLimit(maxBytes, unlimited)
	if !ok || max <= 0 {
		return ioFailure[Option[string]](IoError_InvalidInput{})
	}
	source, ok := input.(lineSource)
	if !ok {
		return readLineByByte(ctx, input, max)
	}
	mu, ahead := source.lineBuffer()
	// A whole line already buffered is sliced out under one lock, with no
	// intermediate copy.
	mu.Lock()
	if i := bytes.IndexByte(ahead.buf, '\n'); i >= 0 && lineLength(ahead.buf[:i]) < max {
		line := ahead.buf[:i]
		ahead.buf = ahead.buf[i+1:]
		mu.Unlock()
		if n := len(line); n > 0 && line[n-1] == '\r' {
			line = line[:n-1]
		}
		if !utf8.Valid(line) {
			return ioFailure[Option[string]](IoError_InvalidData{})
		}
		return Ok[Option[string], IoError](Some(string(line)))
	}
	mu.Unlock()
	take := func() []byte {
		mu.Lock()
		defer mu.Unlock()
		data, _ := ahead.take(0)
		return data
	}
	unread := func(rest []byte) {
		mu.Lock()
		ahead.buf = rest
		mu.Unlock()
	}
	var b []byte
	for {
		chunk := take()
		if len(chunk) == 0 {
			v := input.Read(ctx, Some(65536))
			if v.Failed {
				return Fail[Option[string]](v.Err)
			}
			if !v.Val.Some {
				if len(b) == 0 {
					return Ok[Option[string], IoError](None[string]())
				}
				break
			}
			chunk = v.Val.Val.Data
		}
		if i := bytes.IndexByte(chunk, '\n'); i >= 0 {
			// An over-long line is dropped; the lines after it stay readable.
			if rest := chunk[i+1:]; len(rest) > 0 {
				unread(rest)
			}
			b = append(b, chunk[:i]...)
			if lineLength(b) >= max {
				return ioFailure[Option[string]](IoError_LimitExceeded{})
			}
			if len(b) > 0 && b[len(b)-1] == '\r' {
				b = b[:len(b)-1]
			}
			break
		}
		b = append(b, chunk...)
		if len(b) > max {
			return ioFailure[Option[string]](IoError_LimitExceeded{})
		}
	}
	if !utf8.Valid(b) {
		return ioFailure[Option[string]](IoError_InvalidData{})
	}
	return Ok[Option[string], IoError](Some(string(b)))
}

// lineLength is the length of line without a trailing carriage return, which
// belongs to the line ending and does not count against a limit.
func lineLength(line []byte) int {
	if n := len(line); n > 0 && line[n-1] == '\r' {
		return n - 1
	}
	return len(line)
}

func readLineByByte(ctx *Execution, input ReadStream, max int) Result[Option[string], IoError] {
	var b []byte
	for {
		v := input.Read(ctx, Some(1))
		if v.Failed {
			return Fail[Option[string]](v.Err)
		}
		if !v.Val.Some {
			if len(b) == 0 {
				return Ok[Option[string], IoError](None[string]())
			}
			break
		}
		data := v.Val.Val.Data
		if len(data) != 1 {
			return ioFailure[Option[string]](IoError_Failed{Message: "invalid stream chunk"})
		}
		if data[0] == '\n' {
			if len(b) > 0 && b[len(b)-1] == '\r' {
				b = b[:len(b)-1]
			}
			if len(b) >= max {
				return ioFailure[Option[string]](IoError_LimitExceeded{})
			}
			break
		}
		if len(b) >= max {
			return ioFailure[Option[string]](IoError_LimitExceeded{})
		}
		b = append(b, data[0])
	}
	if !utf8.Valid(b) {
		return ioFailure[Option[string]](IoError_InvalidData{})
	}
	return Ok[Option[string], IoError](Some(string(b)))
}
