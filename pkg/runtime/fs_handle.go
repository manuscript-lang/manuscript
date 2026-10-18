package msruntime

import (
	"errors"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"github.com/fsnotify/fsnotify"
	"github.com/manuscript-lang/manuscript/internal/hostos"
)

// fsCaseName is the case name of a filesystem error, used when an error
// crosses into the I/O domain.
func fsCaseName(e FileSystemError) string {
	switch e := e.(type) {
	case FileSystemError_InvalidInput:
		return "InvalidInput"
	case FileSystemError_InvalidData:
		return "InvalidData"
	case FileSystemError_LimitExceeded:
		return "LimitExceeded"
	case FileSystemError_NotFound:
		return "NotFound"
	case FileSystemError_AlreadyExists:
		return "AlreadyExists"
	case FileSystemError_NotEmpty:
		return "NotEmpty"
	case FileSystemError_PermissionDenied:
		return "PermissionDenied"
	case FileSystemError_Unsupported:
		return "Unsupported"
	case FileSystemError_Closed:
		return "Closed"
	case FileSystemError_Failed:
		return e.Message
	}
	return ""
}

// ioErrorOf converts a filesystem error to the I/O domain: Closed and
// InvalidInput keep their identity, every other case becomes Failed carrying
// the case name (or the Failed message).
func ioErrorOf(e FileSystemError) IoError {
	switch e.(type) {
	case FileSystemError_Closed:
		return IoError_Closed{}
	case FileSystemError_InvalidInput:
		return IoError_InvalidInput{}
	}
	return IoError_Failed{Message: fsCaseName(e)}
}

// osFileHandle serializes offset-changing operations. Close first closes the
// OS descriptor to interrupt pollable I/O, then joins admitted calls.
type osFileHandle struct {
	mu     sync.Mutex
	file   *os.File
	closed bool
	// noRead and noWrite record the open mode so misuse is InvalidInput on
	// every host instead of a platform-specific errno.
	noRead, noWrite bool
	active          sync.WaitGroup
	released        chan struct{}
	gate            chan struct{}
	// ahead holds bytes ReadLine took from the reader beyond the current line.
	ahead readAhead
}

var _ FileHandle = (*osFileHandle)(nil)

// rewindAhead returns read-ahead bytes to the file so position-based
// operations see them.
func (h *osFileHandle) rewindAhead() {
	h.mu.Lock()
	ahead, _ := h.ahead.take(0)
	h.mu.Unlock()
	if len(ahead) > 0 {
		h.file.Seek(-int64(len(ahead)), io.SeekCurrent)
	}
}

func (h *osFileHandle) Close(*Execution) Unit {
	h.mu.Lock()
	if h.released == nil {
		h.released = make(chan struct{})
	}
	done := h.released
	if h.closed {
		h.mu.Unlock()
		<-done
		return Unit{}
	}
	h.closed = true
	h.mu.Unlock()
	h.file.Close()
	h.active.Wait()
	close(done)
	return Unit{}
}

type opKind int

const (
	opAny opKind = iota
	opRead
	opWrite
)

// handleOp admits one operation on h: closed handles fail, operations are
// serialized, cancellation interrupts blocked I/O, and the open mode is
// enforced. finish maps the OS outcome, reporting Closed when the handle was
// closed meanwhile.
func handleOp[T any](h *osFileHandle, ctx *Execution, kind opKind, body func(finish func(T, error) Result[T, FileSystemError]) Result[T, FileSystemError]) Result[T, FileSystemError] {
	h.mu.Lock()
	if h.gate == nil {
		h.gate = make(chan struct{}, 1)
	}
	gate, closed := h.gate, h.closed
	h.mu.Unlock()
	if closed {
		return fsFail[T](FileSystemError_Closed{})
	}
	select {
	case gate <- struct{}{}:
	case <-ctx.Context.Done():
		CheckCancelled(ctx)
	}
	defer func() { <-gate }()
	h.mu.Lock()
	if h.closed {
		h.mu.Unlock()
		return fsFail[T](FileSystemError_Closed{})
	}
	h.active.Add(1)
	h.mu.Unlock()
	defer h.active.Done()
	CheckCancelled(ctx)
	h.rewindAhead()
	stop := interruptDeadline(ctx, func(t time.Time) error { h.file.SetReadDeadline(t); return h.file.SetWriteDeadline(t) })
	defer stop()
	finish := func(v T, err error) Result[T, FileSystemError] {
		CheckCancelled(ctx)
		h.mu.Lock()
		closed := h.closed
		h.mu.Unlock()
		if closed {
			return fsFail[T](FileSystemError_Closed{})
		}
		return fsDone(v, err)
	}
	if kind == opRead && h.noRead || kind == opWrite && h.noWrite {
		return fsInvalid[T]()
	}
	return body(finish)
}

// withClosed runs fn under the handle lock, failing when the handle is closed.
func withClosed[T any](h *osFileHandle, fn func() (T, error)) (T, bool, error) {
	h.mu.Lock()
	defer h.mu.Unlock()
	var zero T
	if h.closed {
		return zero, true, nil
	}
	v, err := fn()
	return v, false, err
}

func (h *osFileHandle) Reader(*Execution) ReadStream  { return handleReader{h} }
func (h *osFileHandle) Writer(*Execution) WriteStream { return handleWriter{h} }

func (h *osFileHandle) Read(ctx *Execution, maxBytes Option[int]) Result[Option[*Bytes], FileSystemError] {
	n, ok := optionLimit(maxBytes, 65536)
	if !ok {
		return fsInvalid[Option[*Bytes]]()
	}
	return handleOp(h, ctx, opRead, func(finish func(Option[*Bytes], error) Result[Option[*Bytes], FileSystemError]) Result[Option[*Bytes], FileSystemError] {
		if n <= 0 {
			return fsInvalid[Option[*Bytes]]()
		}
		data := make([]byte, int(min(n, 65536)))
		count, err := h.file.Read(data)
		eof := err == io.EOF
		if eof {
			err = nil
		}
		return finish(Option[*Bytes]{Val: NewBytes(data[:count]), Some: !(count == 0 && eof)}, err)
	})
}

func (h *osFileHandle) ReadAt(ctx *Execution, offset int, maxBytes Option[int]) Result[*Bytes, FileSystemError] {
	n, ok := optionLimit(maxBytes, 65536)
	if !ok {
		return fsInvalid[*Bytes]()
	}
	return handleOp(h, ctx, opRead, func(finish func(*Bytes, error) Result[*Bytes, FileSystemError]) Result[*Bytes, FileSystemError] {
		if n <= 0 || offset < 0 {
			return fsInvalid[*Bytes]()
		}
		data := make([]byte, int(min(n, 65536)))
		count, err := h.file.ReadAt(data, int64(offset))
		if err == io.EOF {
			err = nil
		}
		return finish(NewBytes(data[:count]), err)
	})
}

func (h *osFileHandle) ReadFile(ctx *Execution, maxBytes Option[int]) Result[*Bytes, FileSystemError] {
	n, ok := optionLimit(maxBytes, unlimited)
	if !ok {
		return fsInvalid[*Bytes]()
	}
	return handleOp(h, ctx, opRead, func(finish func(*Bytes, error) Result[*Bytes, FileSystemError]) Result[*Bytes, FileSystemError] {
		b, code := readBounded(ctx, h.file, n)
		if code != "" {
			return fsFail[*Bytes](readFailure(code))
		}
		return finish(NewBytes(b), nil)
	})
}

func (h *osFileHandle) Write(ctx *Execution, data string) Result[Unit, FileSystemError] {
	return h.WriteBytes(ctx, NewBytes([]byte(data)))
}

func (h *osFileHandle) WriteBytes(ctx *Execution, data *Bytes) Result[Unit, FileSystemError] {
	return handleOp(h, ctx, opWrite, func(finish func(Unit, error) Result[Unit, FileSystemError]) Result[Unit, FileSystemError] {
		_, err := writeChunks(ctx, h.file, data.Data, nil)
		return finish(Unit{}, err)
	})
}

func (h *osFileHandle) AppendFile(ctx *Execution, data string) Result[Unit, FileSystemError] {
	return h.AppendFileBytes(ctx, NewBytes([]byte(data)))
}

func (h *osFileHandle) AppendFileBytes(ctx *Execution, data *Bytes) Result[Unit, FileSystemError] {
	return h.WriteBytes(ctx, data)
}

func (h *osFileHandle) WriteAt(ctx *Execution, offset int, data string) Result[Unit, FileSystemError] {
	return h.WriteAtBytes(ctx, offset, NewBytes([]byte(data)))
}

func (h *osFileHandle) WriteAtBytes(ctx *Execution, offset int, data *Bytes) Result[Unit, FileSystemError] {
	return handleOp(h, ctx, opWrite, func(finish func(Unit, error) Result[Unit, FileSystemError]) Result[Unit, FileSystemError] {
		if offset < 0 {
			return fsInvalid[Unit]()
		}
		_, err := writeChunks(ctx, h.file, data.Data, &offset)
		return finish(Unit{}, err)
	})
}

func (h *osFileHandle) ReadVectors(ctx *Execution, sizes *List[int], offset int) Result[*List[*Bytes], FileSystemError] {
	return handleOp(h, ctx, opRead, func(finish func(*List[*Bytes], error) Result[*List[*Bytes], FileSystemError]) Result[*List[*Bytes], FileSystemError] {
		var total int
		if offset < -1 {
			return fsInvalid[*List[*Bytes]]()
		}
		for _, n := range sizes.Items {
			if n < 0 || n > 65536 || total > 16*1024*1024-n {
				return fsInvalid[*List[*Bytes]]()
			}
			total += n
		}
		var result []*Bytes
		for _, size := range sizes.Items {
			CheckCancelled(ctx)
			b := make([]byte, int(size))
			var n int
			var err error
			if offset == -1 {
				n, err = h.file.Read(b)
			} else {
				n, err = h.file.ReadAt(b, int64(offset))
				offset += int(n)
			}
			result = append(result, NewBytes(b[:n]))
			if err != nil && err != io.EOF {
				return finish(nil, err)
			}
		}
		return finish(NewList(result...), nil)
	})
}

func (h *osFileHandle) WriteVectors(ctx *Execution, buffers *List[*Bytes], offset int) Result[Unit, FileSystemError] {
	return handleOp(h, ctx, opWrite, func(finish func(Unit, error) Result[Unit, FileSystemError]) Result[Unit, FileSystemError] {
		if offset < -1 {
			return fsInvalid[Unit]()
		}
		for _, v := range buffers.Items {
			var ptr *int
			if offset != -1 {
				ptr = &offset
			}
			n, err := writeChunks(ctx, h.file, v.Data, ptr)
			if offset != -1 {
				offset += n
			}
			if err != nil {
				return finish(Unit{}, err)
			}
		}
		return finish(Unit{}, nil)
	})
}

func (h *osFileHandle) Seek(ctx *Execution, offset, origin int) Result[int, FileSystemError] {
	return handleOp(h, ctx, opAny, func(finish func(int, error) Result[int, FileSystemError]) Result[int, FileSystemError] {
		if origin < 0 || origin > 2 || offset < 0 && origin == 0 {
			return fsInvalid[int]()
		}
		n, err := h.file.Seek(int64(offset), origin)
		if err == nil {
			n = int64(FitInt(n))
		}
		return finish(int(n), err)
	})
}

func (h *osFileHandle) Stat(ctx *Execution) Result[*FileInfo, FileSystemError] {
	return handleOp(h, ctx, opAny, func(finish func(*FileInfo, error) Result[*FileInfo, FileSystemError]) Result[*FileInfo, FileSystemError] {
		info, err := h.file.Stat()
		if err != nil {
			return finish(nil, err)
		}
		if !utf8.ValidString(info.Name()) {
			return fsFail[*FileInfo](FileSystemError_Unsupported{})
		}
		birth, closed, _ := withClosed(h, func() (time.Time, error) { return hostos.BirthFile(h.file), nil })
		if closed {
			return fsFail[*FileInfo](FileSystemError_Closed{})
		}
		return finish(fileInfoOf(info, birth), nil)
	})
}

func (h *osFileHandle) Truncate(ctx *Execution, size int) Result[Unit, FileSystemError] {
	return handleOp(h, ctx, opWrite, func(finish func(Unit, error) Result[Unit, FileSystemError]) Result[Unit, FileSystemError] {
		if size < 0 {
			return fsInvalid[Unit]()
		}
		return finish(Unit{}, h.file.Truncate(int64(size)))
	})
}

func (h *osFileHandle) Sync(ctx *Execution) Result[Unit, FileSystemError] {
	return handleOp(h, ctx, opAny, func(finish func(Unit, error) Result[Unit, FileSystemError]) Result[Unit, FileSystemError] {
		return finish(Unit{}, h.file.Sync())
	})
}

func (h *osFileHandle) DataSync(ctx *Execution) Result[Unit, FileSystemError] {
	return handleOp(h, ctx, opAny, func(finish func(Unit, error) Result[Unit, FileSystemError]) Result[Unit, FileSystemError] {
		_, closed, err := withClosed(h, func() (Unit, error) { return Unit{}, hostos.DataSync(h.file) })
		if closed {
			return fsFail[Unit](FileSystemError_Closed{})
		}
		return finish(Unit{}, err)
	})
}

func (h *osFileHandle) Chmod(ctx *Execution, mode int) Result[Unit, FileSystemError] {
	return handleOp(h, ctx, opAny, func(finish func(Unit, error) Result[Unit, FileSystemError]) Result[Unit, FileSystemError] {
		if mode < 0 || mode > 07777 {
			return fsInvalid[Unit]()
		}
		return finish(Unit{}, h.file.Chmod(fileMode(mode)))
	})
}

func (h *osFileHandle) Chown(ctx *Execution, uid, gid int) Result[Unit, FileSystemError] {
	return handleOp(h, ctx, opAny, func(finish func(Unit, error) Result[Unit, FileSystemError]) Result[Unit, FileSystemError] {
		if uid < -1 || gid < -1 || uid > 2147483647 || gid > 2147483647 {
			return fsInvalid[Unit]()
		}
		return finish(Unit{}, h.file.Chown(int(uid), int(gid)))
	})
}

func (h *osFileHandle) SetTimes(ctx *Execution, accessed, modified Timestamp) Result[Unit, FileSystemError] {
	return handleOp(h, ctx, opAny, func(finish func(Unit, error) Result[Unit, FileSystemError]) Result[Unit, FileSystemError] {
		_, closed, err := withClosed(h, func() (Unit, error) { return Unit{}, hostos.FileTimes(h.file, timeOf(accessed), timeOf(modified)) })
		if closed {
			return fsFail[Unit](FileSystemError_Closed{})
		}
		if errors.Is(err, errors.ErrUnsupported) {
			return fsFail[Unit](FileSystemError_Unsupported{})
		}
		return finish(Unit{}, err)
	})
}

func (h *osFileHandle) ReadLines(ctx *Execution, maxBytes Option[int], maxLines Option[int]) Result[*List[string], FileSystemError] {
	max, ok := optionLimit(maxBytes, unlimited)
	lines, ok2 := optionLimit(maxLines, unlimited)
	if !ok || !ok2 {
		return fsInvalid[*List[string]]()
	}
	v := h.ReadFile(ctx, Some(max))
	if v.Failed {
		return fsFail[*List[string]](v.Err)
	}
	data := v.Val.Data
	if !utf8.Valid(data) {
		return fsFail[*List[string]](FileSystemError_InvalidData{})
	}
	var items []string
	if len(data) > 0 {
		parts := strings.Split(string(data), "\n")
		if parts[len(parts)-1] == "" {
			parts = parts[:len(parts)-1]
		}
		if len(parts) > lines {
			return fsFail[*List[string]](FileSystemError_LimitExceeded{})
		}
		for _, line := range parts {
			items = append(items, strings.TrimSuffix(line, "\r"))
		}
	}
	return fsOK(NewList(items...))
}

// handleReader and handleWriter are the stream views of a file handle.
type handleReader struct{ h *osFileHandle }
type handleWriter struct{ h *osFileHandle }

var (
	_ ReadStream  = handleReader{}
	_ lineSource  = handleReader{}
	_ WriteStream = handleWriter{}
)

func (r handleReader) lineBuffer() (*sync.Mutex, *readAhead) { return &r.h.mu, &r.h.ahead }

func (r handleReader) Close(ctx *Execution) Unit { return r.h.Close(ctx) }

func (r handleReader) Read(ctx *Execution, maxBytes Option[int]) Result[Option[*Bytes], IoError] {
	n := 65536
	if maxBytes.Some && maxBytes.Val >= 0 {
		n = maxBytes.Val
	}
	if !maxBytes.Some || maxBytes.Val >= 0 {
		r.h.mu.Lock()
		data, held := r.h.ahead.take(int(min(n, 65536)))
		r.h.mu.Unlock()
		if held {
			return Ok[Option[*Bytes], IoError](Some(NewBytes(data)))
		}
	}
	v := r.h.Read(ctx, maxBytes)
	if v.Failed {
		return ioFailure[Option[*Bytes]](ioErrorOf(v.Err))
	}
	return Ok[Option[*Bytes], IoError](v.Val)
}

func (w handleWriter) Close(ctx *Execution) Unit { return w.h.Close(ctx) }

func (w handleWriter) Write(ctx *Execution, data string) Result[Unit, IoError] {
	return w.WriteBytes(ctx, NewBytes([]byte(data)))
}

func (w handleWriter) WriteBytes(ctx *Execution, data *Bytes) Result[Unit, IoError] {
	v := w.h.WriteBytes(ctx, data)
	if v.Failed {
		return ioFailure[Unit](ioErrorOf(v.Err))
	}
	return Ok[Unit, IoError](Unit{})
}

func (w handleWriter) Flush(ctx *Execution) Result[Unit, IoError] {
	v := w.h.Sync(ctx)
	if v.Failed {
		return ioFailure[Unit](ioErrorOf(v.Err))
	}
	return Ok[Unit, IoError](Unit{})
}

// osDirectory iterates a directory one entry at a time.
type osDirectory struct {
	mu     sync.Mutex
	file   *os.File
	closed bool
}

var _ Directory = (*osDirectory)(nil)

func (d *osDirectory) Path(*Execution) string {
	d.mu.Lock()
	defer d.mu.Unlock()
	return d.file.Name()
}

func (d *osDirectory) Close(*Execution) Unit {
	d.mu.Lock()
	defer d.mu.Unlock()
	if !d.closed {
		d.closed = true
		d.file.Close()
	}
	return Unit{}
}

func (d *osDirectory) Read(ctx *Execution) Result[Option[*DirectoryEntry], FileSystemError] {
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.closed {
		return fsFail[Option[*DirectoryEntry]](FileSystemError_Closed{})
	}
	CheckCancelled(ctx)
	entries, err := d.file.ReadDir(1)
	CheckCancelled(ctx)
	if err == io.EOF {
		return fsOK(None[*DirectoryEntry]())
	}
	if err != nil {
		return fsDone[Option[*DirectoryEntry]](None[*DirectoryEntry](), err)
	}
	entry := entries[0]
	if !utf8.ValidString(entry.Name()) {
		return fsFail[Option[*DirectoryEntry]](FileSystemError_Unsupported{})
	}
	return fsOK(Some(directoryEntryOf(entry.Name(), entry.IsDir(), entry.Type()&os.ModeSymlink != 0)))
}

// osTemporary is a temporary directory removed when it is closed.
type osTemporary struct {
	mu     sync.Mutex
	path   string
	closed bool
}

var _ TemporaryDirectory = (*osTemporary)(nil)

func (t *osTemporary) Path(*Execution) string {
	t.mu.Lock()
	defer t.mu.Unlock()
	return t.path
}

func (t *osTemporary) Close(ctx *Execution) Unit {
	t.mu.Lock()
	defer t.mu.Unlock()
	if !t.closed {
		if err := removeTree(ctx, t.path); err != nil {
			Raise(err.Error())
		}
		t.closed = true
	}
	return Unit{}
}

type watchStamp struct {
	mode     os.FileMode
	size     int64
	modified time.Time
}

// pollWatcher compares directory snapshots at a fixed interval.
type pollWatcher struct {
	mu        sync.Mutex
	path      string
	recursive bool
	interval  time.Duration
	max       int
	snapshot  map[string]watchStamp
	done      chan struct{}
	closed    bool
	gate      chan struct{}
}

var _ FileWatcher = (*pollWatcher)(nil)

func watchSnapshot(ctx *Execution, p string, recursive bool, max int) (map[string]watchStamp, error) {
	snapshot := map[string]watchStamp{}
	err := filepath.WalkDir(p, func(child string, e os.DirEntry, err error) error {
		CheckCancelled(ctx)
		if err != nil {
			return err
		}
		if len(snapshot) >= max {
			return errLimit
		}
		if !utf8.ValidString(child) {
			return errEncoding
		}
		info, err := e.Info()
		if err != nil {
			return err
		}
		snapshot[child] = watchStamp{info.Mode(), info.Size(), info.ModTime()}
		if child != p && e.IsDir() && !recursive {
			return filepath.SkipDir
		}
		return nil
	})
	return snapshot, err
}

func (w *pollWatcher) Close(*Execution) Unit {
	w.mu.Lock()
	if !w.closed {
		w.closed = true
		close(w.done)
	}
	w.mu.Unlock()
	w.gate <- struct{}{}
	<-w.gate
	return Unit{}
}

func (w *pollWatcher) Next(ctx *Execution) Result[*List[*FileEvent], FileSystemError] {
	select {
	case w.gate <- struct{}{}:
	case <-w.done:
		return fsFail[*List[*FileEvent]](FileSystemError_Closed{})
	case <-ctx.Context.Done():
		CheckCancelled(ctx)
	}
	defer func() { <-w.gate }()
	timer := time.NewTimer(w.interval)
	defer timer.Stop()
	for {
		select {
		case <-w.done:
			return fsFail[*List[*FileEvent]](FileSystemError_Closed{})
		case <-ctx.Context.Done():
			CheckCancelled(ctx)
		case <-timer.C:
		}
		now, err := watchSnapshot(ctx, w.path, w.recursive, w.max)
		if errors.Is(err, os.ErrNotExist) {
			now = map[string]watchStamp{}
			err = nil
		}
		if err != nil {
			return fsFail[*List[*FileEvent]](snapshotError(err))
		}
		changes := map[string]string{}
		for p, stamp := range now {
			old, ok := w.snapshot[p]
			if !ok {
				changes[p] = "rename"
			} else if old != stamp {
				changes[p] = "change"
			}
		}
		for p := range w.snapshot {
			if _, ok := now[p]; !ok {
				changes[p] = "rename"
			}
		}
		w.snapshot = now
		if len(changes) > 0 {
			keys := make([]string, 0, len(changes))
			for p := range changes {
				keys = append(keys, p)
			}
			sort.Strings(keys)
			items := make([]*FileEvent, 0, len(keys))
			for _, p := range keys {
				items = append(items, &FileEvent{Path: p, Kind: changes[p]})
			}
			return fsOK(NewList(items...))
		}
		timer.Reset(w.interval)
	}
}

// nativeWatcher consumes kernel events independently of Next so recursive
// directory admission and transient-event retention do not depend on readers.
type nativeWatcher struct {
	native           *fsnotify.Watcher
	recursive        bool
	max              int
	overflow         string
	watched          map[string]bool
	mu               sync.Mutex
	closed           bool
	terminal         error
	done, workerDone chan struct{}
	events           chan fsnotify.Event
	gate             chan struct{}
}

var _ FileWatcher = (*nativeWatcher)(nil)

func (f *osFileSystem) WatchNative(ctx *Execution, path string, recursive bool, maxEntries, maxEvents Option[int], overflow string) Result[FileWatcher, FileSystemError] {
	max, ok := optionLimit(maxEntries, unlimited)
	events, ok2 := optionLimit(maxEvents, 128)
	p, ok3 := f.path(path)
	if !ok || !ok2 || !ok3 || max <= 0 || events <= 0 || events > 1048576 || overflow != "error" && overflow != "ignore" {
		return fsInvalid[FileWatcher]()
	}
	native, err := fsnotify.NewWatcher()
	if err != nil {
		return fsDone[FileWatcher](nil, err)
	}
	delivered := false
	defer func() {
		if !delivered {
			native.Close()
		}
	}()
	w := &nativeWatcher{native: native, recursive: recursive, max: max, overflow: overflow, watched: map[string]bool{}, done: make(chan struct{}), workerDone: make(chan struct{}), events: make(chan fsnotify.Event, int(events)), gate: make(chan struct{}, 1)}
	if err = w.addTree(p); err != nil {
		return fsFail[FileWatcher](snapshotError(err))
	}
	CheckCancelled(ctx)
	go w.pump()
	delivered = true
	return fsOK[FileWatcher](w)
}

func (w *nativeWatcher) addTree(root string) error {
	return filepath.WalkDir(root, func(path string, entry os.DirEntry, err error) error {
		select {
		case <-w.done:
			return os.ErrClosed
		default:
		}
		if err != nil {
			return err
		}
		if !utf8.ValidString(path) {
			return errEncoding
		}
		if path != root && !entry.IsDir() {
			return nil
		}
		if !w.watched[path] {
			if len(w.watched) >= w.max {
				return errLimit
			}
			if err = w.native.Add(path); err != nil {
				return err
			}
			w.watched[path] = true
		}
		if !w.recursive && entry.IsDir() {
			return filepath.SkipDir
		}
		return nil
	})
}

func (w *nativeWatcher) fail(err error) { w.mu.Lock(); w.terminal = err; w.mu.Unlock() }

func (w *nativeWatcher) pump() {
	defer close(w.workerDone)
	defer close(w.events)
	defer w.native.Close()
	for {
		select {
		case <-w.done:
			return
		case err, ok := <-w.native.Errors:
			if !ok {
				return
			}
			if errors.Is(err, fsnotify.ErrEventOverflow) {
				if w.overflow == "ignore" {
					continue
				}
				err = errLimit
			}
			w.fail(err)
			return
		case event, ok := <-w.native.Events:
			if !ok {
				return
			}
			if event.Op&(fsnotify.Remove|fsnotify.Rename) != 0 {
				for watched := range w.watched {
					if watched == event.Name || strings.HasPrefix(watched, event.Name+string(os.PathSeparator)) {
						delete(w.watched, watched)
					}
				}
			}
			if w.recursive && event.Has(fsnotify.Create) {
				if info, err := os.Lstat(event.Name); err == nil && info.IsDir() {
					if err = w.addTree(event.Name); err != nil && !errors.Is(err, os.ErrNotExist) {
						w.fail(err)
						return
					}
				}
			}
			if !utf8.ValidString(event.Name) {
				w.fail(errEncoding)
				return
			}
			select {
			case <-w.done:
				return
			case w.events <- event:
			default:
				if w.overflow == "error" {
					w.fail(errLimit)
					return
				}
			}
		}
	}
}

// failure reports the watcher's terminal condition, if any.
func (w *nativeWatcher) failure() (FileSystemError, bool) {
	w.mu.Lock()
	err, closed := w.terminal, w.closed
	w.mu.Unlock()
	if closed {
		return FileSystemError_Closed{}, true
	}
	if err == nil {
		return nil, false
	}
	return snapshotError(err), true
}

func (w *nativeWatcher) Close(*Execution) Unit {
	w.mu.Lock()
	if !w.closed {
		w.closed = true
		close(w.done)
	}
	w.mu.Unlock()
	w.native.Close()
	<-w.workerDone
	w.gate <- struct{}{}
	<-w.gate
	return Unit{}
}

func (w *nativeWatcher) Next(ctx *Execution) Result[*List[*FileEvent], FileSystemError] {
	select {
	case w.gate <- struct{}{}:
	case <-ctx.Context.Done():
		CheckCancelled(ctx)
	case <-w.done:
		return fsFail[*List[*FileEvent]](FileSystemError_Closed{})
	}
	defer func() { <-w.gate }()
	if e, failed := w.failure(); failed {
		return fsFail[*List[*FileEvent]](e)
	}
	select {
	case <-ctx.Context.Done():
		CheckCancelled(ctx)
	case <-w.done:
		return fsFail[*List[*FileEvent]](FileSystemError_Closed{})
	case event, ok := <-w.events:
		if e, failed := w.failure(); failed {
			return fsFail[*List[*FileEvent]](e)
		}
		if !ok {
			return fsFail[*List[*FileEvent]](FileSystemError_Closed{})
		}
		CheckCancelled(ctx)
		kind := "change"
		if event.Op&(fsnotify.Create|fsnotify.Remove|fsnotify.Rename) != 0 {
			kind = "rename"
		}
		return fsOK(NewList(&FileEvent{Path: event.Name, Kind: kind}))
	}
	Raise("unreachable watch wait")
	return fsFail[*List[*FileEvent]](FileSystemError_Closed{})
}
