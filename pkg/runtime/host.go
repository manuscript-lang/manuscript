package msruntime

import (
	"context"
	"fmt"
	"io"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"time"
	"unicode/utf8"
)

type Native interface{ Operation(string) Function }
type stream struct {
	admitted            int
	mu                  sync.Mutex
	file                *os.File
	closed, owned       bool
	resultType          string
	readGate, writeGate chan struct{}
	closing, released   chan struct{}
	active              sync.WaitGroup
	releaseFault        error
}

func (s *stream) initialize() {
	if s.closing != nil {
		return
	}
	s.closing = make(chan struct{})
	s.released = make(chan struct{})
	s.readGate = make(chan struct{}, 1)
	s.writeGate = make(chan struct{}, 1)
	s.readGate <- struct{}{}
	s.writeGate <- struct{}{}
}
func (s *stream) close() {
	s.mu.Lock()
	s.initialize()
	if s.closed {
		released := s.released
		s.mu.Unlock()
		<-released
		if s.releaseFault != nil {
			Panic(s.releaseFault.Error())
		}
		return
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
		Panic(s.releaseFault.Error())
	}
}
func (s *stream) Operation(name string) Function {
	if name == "close" {
		return NewFunction(nil, "Unit", func(_ *Execution, _ []Value) Value { s.close(); return Unit{} })
	}
	labels := []string{}
	if name == "read" {
		labels = []string{"max_bytes"}
	}
	if name == "write" {
		labels = []string{"data"}
	}
	return NewFunction(labels, s.resultType, func(ctx *Execution, args []Value) Value {
		s.mu.Lock()
		s.initialize()
		gate := s.readGate
		if name != "read" {
			gate = s.writeGate
		}
		closing := s.closing
		closed := s.closed
		s.mu.Unlock()
		if closed {
			return ioError(s.resultType, "Closed", "")
		}
		select {
		case <-gate:
		case <-closing:
			return ioError(s.resultType, "Closed", "")
		case <-ctx.Context.Done():
			CheckCancelled(ctx)
		}
		defer func() { gate <- struct{}{} }()
		s.mu.Lock()
		if s.closed {
			s.mu.Unlock()
			return ioError(s.resultType, "Closed", "")
		}
		s.active.Add(1)
		s.admitted++
		s.mu.Unlock()
		defer func() { s.mu.Lock(); s.admitted--; s.mu.Unlock(); s.active.Done() }()
		CheckCancelled(ctx)
		// Pollable files support deadlines. Regular files complete synchronously.
		deadline := s.file.SetReadDeadline
		if name != "read" {
			deadline = s.file.SetWriteDeadline
		}
		interruptDone := make(chan struct{})
		stop := context.AfterFunc(ctx.Context, func() { defer close(interruptDone); deadline(time.Now()) })
		defer func() {
			if !stop() {
				<-interruptDone
			}
			deadline(time.Time{})
		}()
		switch name {
		case "read":
			n := nativeStreamReadSize(args[0])
			if n <= 0 {
				return ioError(s.resultType, "InvalidInput", "")
			}
			if n > 64*1024 {
				n = 64 * 1024
			}
			data := make([]byte, int(n))
			read, err := s.file.Read(data)
			CheckCancelled(ctx)
			if err != nil && err != io.EOF {
				s.mu.Lock()
				closed := s.closed
				s.mu.Unlock()
				if closed {
					return ioError(s.resultType, "Closed", "")
				}
				return ioError(s.resultType, "Failed", err.Error())
			}
			if read == 0 && err == io.EOF {
				return Alternative{s.resultType, "ok", []Value{optional("@std/Bytes", nil, false)}}
			}
			return Alternative{s.resultType, "ok", []Value{optional("@std/Bytes", Bytes{data[:read]}, true)}}
		case "write":
			data := args[0].(Bytes).Items
			for len(data) > 0 {
				n, err := s.file.Write(data)
				CheckCancelled(ctx)
				if err != nil {
					s.mu.Lock()
					closed := s.closed
					s.mu.Unlock()
					if closed {
						return ioError(s.resultType, "Closed", "")
					}
					return ioError(s.resultType, "Failed", err.Error())
				}
				if n == 0 {
					return ioError(s.resultType, "Failed", "short write")
				}
				data = data[n:]
			}
			return Alternative{s.resultType, "ok", []Value{Unit{}}}
		case "flush":
			return Alternative{s.resultType, "ok", []Value{Unit{}}}
		}
		return Panic("unavailable stream operation")
	})
}

func ioError(result, tag, message string) Value {
	fields := []Value{}
	if tag == "Failed" {
		fields = append(fields, message)
	}
	return Alternative{result, "error", []Value{Alternative{"@std/IoError", tag, fields}}}
}

type files struct{ directory string }

func (f *files) Operation(name string) Function {
	return NewAcquisition([]string{"path"}, "@std/Result[@std/File][@std/IoError]", func(ctx *Execution, args []Value) Value {
		CheckCancelled(ctx)
		name := args[0].(string)
		if strings.ContainsRune(name, 0) {
			return ioError("@std/Result[@std/File][@std/IoError]", "InvalidInput", "")
		}
		if !filepath.IsAbs(name) {
			var ok bool
			name, ok = libraryHostPath(f.directory, name)
			if !ok {
				return ioError("@std/Result[@std/File][@std/IoError]", "Unavailable", "")
			}
		}
		file, err := os.Open(name)
		if err != nil {
			return ioError("@std/Result[@std/File][@std/IoError]", "Unavailable", "")
		}
		resource := &stream{file: file, owned: true, resultType: "@std/Result[@std/Optional[@std/Bytes]][@std/IoError]"}
		if ctx.Context.Err() != nil {
			file.Close()
			CheckCancelled(ctx)
		}
		return Alternative{"@std/Result[@std/File][@std/IoError]", "ok", []Value{ViewOf("@std/File", resource)}}
	}, func(ctx *Execution, value Value) {
		result := value.(Alternative)
		if result.Tag == "ok" {
			Invoke(Shield(ctx), Bind(result.Fields[0], "", "close"), nil)
		}
	})
}

type clock struct {
	domain *clockDomain
	start  time.Time
}

func (c *clock) Operation(name string) Function {
	return NewFunction(nil, "@std/Instant", func(_ *Execution, _ []Value) Value { return Instant{c.domain, int64(time.Since(c.start))} })
}

// hostRoots are private to one CLI run or test. Derived execution contexts share
// the same roots; importing an accessor never creates another service instance.
type hostRoots struct {
	once      sync.Once
	arguments []string
	values    map[string]Value
	err       error
}

func (h *hostRoots) initialize() error {
	h.once.Do(func() { h.values, h.err = newHostValues(h.arguments) })
	return h.err
}

func hostValue(ctx *Execution, name string) Value {
	if ctx == nil || ctx.Host == nil {
		return Panic("host services are unavailable in this execution")
	}
	if err := ctx.Host.initialize(); err != nil {
		return Panic(err.Error())
	}
	return ctx.Host.values[name]
}

func init() {
	for _, root := range []struct{ module, name, result string }{
		{"cli", "arguments", "List[String]"},
		{"cli", "environment", "Map[String][String]"},
		{"io", "stdin", "ReadStream"},
		{"io", "stdout", "WriteStream"},
		{"io", "stderr", "WriteStream"},
		{"io", "files", "Files"},
		{"fs", "filesystem", "FileSystem"},
		{"net", "network", "Network"},
		{"process", "commands", "Commands"},
		{"process", "control", "ProcessControl"},
		{"time", "clock", "Clock"},
		{"time", "wall_clock", "WallClock"},
		{"random", "entropy", "Entropy"},
		{"system", "system", "System"},
	} {
		libraryAdd(root.module, root.name, root.result, nil, func(ctx *Execution, _ string, _ []Value) Value {
			return hostValue(ctx, root.name)
		})
	}
}

func newHostValues(arguments []string) (map[string]Value, error) {
	values := make([]Value, len(arguments))
	for i, a := range arguments {
		if !utf8.ValidString(a) {
			return nil, fmt.Errorf("process arguments are not valid UTF-8")
		}
		values[i] = a
	}
	environment := &Map{Type: "@std/Map[String][String]"}
	for _, entry := range os.Environ() {
		if !utf8.ValidString(entry) {
			return nil, fmt.Errorf("process environment is not valid UTF-8")
		}
		name, value, ok := strings.Cut(entry, "=")
		if ok {
			replaced := false
			for i, e := range environment.Entries {
				if e.Key == name {
					environment.Entries[i].Value = value
					replaced = true
					break
				}
			}
			if !replaced {
				environment.Entries = append(environment.Entries, Entry{name, value})
			}
		}
	}
	return map[string]Value{"filesystem": ViewOf("@std/FileSystem", &libraryFileSystem{""}), "control": ViewOf("@std/ProcessControl", libraryProcessControl{}), "entropy": ViewOf("@std/Entropy", libraryEntropy{}), "wall_clock": ViewOf("@std/WallClock", libraryWallClock{}), "system": ViewOf("@std/System", &librarySystem{""}), "arguments": &List{"@std/List[String]", values}, "environment": environment, "stdin": ViewOf("@std/ReadStream", &stream{file: os.Stdin, resultType: "@std/Result[@std/Optional[@std/Bytes]][@std/IoError]"}), "stdout": ViewOf("@std/WriteStream", &stream{file: os.Stdout, resultType: "@std/Result[Unit][@std/IoError]"}), "stderr": ViewOf("@std/WriteStream", &stream{file: os.Stderr, resultType: "@std/Result[Unit][@std/IoError]"}), "files": ViewOf("@std/Files", &files{""}), "network": ViewOf("@std/Network", &network{}), "commands": ViewOf("@std/Commands", &commands{}), "clock": ViewOf("@std/Clock", &clock{&clockDomain{}, time.Now()})}, nil
}
func RunMain(main Value, arguments []string) (exit int) {
	exit = 70
	defer FlushDiagnostics()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	signals := make(chan os.Signal, 1)
	signal.Notify(signals, os.Interrupt, syscall.SIGTERM)
	defer signal.Stop(signals)
	done := make(chan struct{})
	defer close(done)
	var mu sync.Mutex
	signalExit := 0
	markConcurrent()
	go func() {
		select {
		case s := <-signals:
			mu.Lock()
			if s == os.Interrupt {
				signalExit = 130
			} else {
				signalExit = 143
			}
			mu.Unlock()
			cancel()
		case <-done:
		}
	}()
	execution := &Execution{Context: ctx, Lifetime: &workLifetime{}, Host: &hostRoots{arguments: arguments}, calls: &callState{}}
	defer func() {
		if r := recover(); r != nil {
			if _, ok := r.(cancelled); ok {
				mu.Lock()
				exit = signalExit
				mu.Unlock()
				if exit == 0 {
					exit = 70
				}
			} else {
				fmt.Fprintln(os.Stderr, r)
				exit = 70
			}
		} else if ctx.Err() != nil {
			mu.Lock()
			exit = signalExit
			mu.Unlock()
			if exit == 0 {
				exit = 70
			}
		}
	}()
	if err := execution.Host.initialize(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 70
	}
	// Host roots remain available until main and every joined operation finish.
	defer Cleanup(execution, hostValue(execution, "stdin"))
	defer Cleanup(execution, hostValue(execution, "stdout"))
	defer Cleanup(execution, hostValue(execution, "stderr"))
	defer Cleanup(execution, hostValue(execution, "network"))
	defer FinishExecution(execution)
	value := Invoke(execution, main, nil).(int64)
	CheckCancelled(execution)
	if value < 0 || value > 125 {
		Panic("main exit code must be between 0 and 125; return 0 for success or a small positive Int for failure (126 and above are reserved by shells)")
	}
	return int(value)
}
