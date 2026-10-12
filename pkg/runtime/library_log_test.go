package msruntime

import (
	"bytes"
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

type logTestStream struct {
	data bytes.Buffer
}

func (s *logTestStream) Operation(name string) Function {
	return NewFunction([]string{"data"}, libraryRuntimeType(libraryResult("Unit", "IoError")), func(_ *Execution, a []Value) Value {
		if name == "write" {
			s.data.Write(a[0].(Bytes).Items)
		}
		return libraryOK(libraryRuntimeType(libraryResult("Unit", "IoError")), Unit{})
	})
}

func TestLogStructuredTimestampAndInvalidData(t *testing.T) {
	ctx := RootExecution()
	output := &logTestStream{}
	transport := newLogTransport(output, nil)
	defer networkingInvoke(ctx, transport, "close")
	logger := librarySuccess(t, libraryCall(t, "log/create", transport, nil, nil, nil, nil))
	before := time.Now().UnixMilli()
	librarySuccess(t, networkingInvoke(ctx, logger, "info", "hello\nworld", nil))
	after := time.Now().UnixMilli()
	var record map[string]json.RawMessage
	if err := json.Unmarshal(bytes.TrimSpace(output.data.Bytes()), &record); err != nil {
		t.Fatal(err)
	}
	var timestamp int64
	if err := json.Unmarshal(record["time"], &timestamp); err != nil || timestamp < before || timestamp > after {
		t.Fatalf("timestamp=%d err=%v", timestamp, err)
	}
	if string(record["level"]) != "30" || string(record["msg"]) != `"hello\nworld"` || bytes.Count(output.data.Bytes(), []byte{'\n'}) != 1 {
		t.Fatal(output.data.String())
	}
	length := output.data.Len()
	cycle := &Map{Type: "@std/Map[String][@std/JsonValue]"}
	cycle.Entries = []Entry{{"cycle", logJSON("ObjectValue", cycle)}}
	libraryFailure(t, networkingInvoke(ctx, logger, "info", "cyclic", cycle), "InvalidData")
	if output.data.Len() != length {
		t.Fatal("invalid data wrote bytes")
	}
}

func TestLogConcurrentFileRecordsAndLevels(t *testing.T) {
	ctx := RootExecution()
	path := filepath.Join(t.TempDir(), "events.ndjson")
	transport := librarySuccess(t, libraryCall(t, "log/file_transport", path))
	logger := librarySuccess(t, libraryCall(t, "log/create", transport, nil, nil, false, nil))
	var workers sync.WaitGroup
	failures := make(chan Value, 64)
	for i := 0; i < 32; i++ {
		workers.Add(1)
		go func() {
			defer workers.Done()
			for j := 0; j < 20; j++ {
				networkingInvoke(ctx, logger, "set_level", Alternative{Type: "@std/LogLevel", Tag: "Trace"})
				networkingInvoke(ctx, logger, "enabled", Alternative{Type: "@std/LogLevel", Tag: "Info"})
				result := networkingInvoke(ctx, logger, "info", "concurrent", nil).(Alternative)
				if result.Tag != "ok" {
					failures <- result
					return
				}
			}
		}()
	}
	workers.Wait()
	close(failures)
	for failure := range failures {
		t.Errorf("log failure: %#v", failure)
	}
	librarySuccess(t, networkingInvoke(ctx, logger, "flush"))
	networkingInvoke(ctx, transport, "close")
	networkingInvoke(ctx, transport, "close")
	libraryFailure(t, networkingInvoke(ctx, logger, "info", "closed", nil), "Closed")
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	lines := strings.Split(strings.TrimSuffix(string(data), "\n"), "\n")
	if len(lines) != 640 {
		t.Fatal(len(lines))
	}
	for _, line := range lines {
		if line != `{"level":30,"msg":"concurrent"}` {
			t.Fatalf("interleaved record: %s", line)
		}
	}
}

type logBlockingStream struct{ started chan struct{} }

func (s *logBlockingStream) Operation(name string) Function {
	return NewFunction([]string{"data"}, libraryRuntimeType(libraryResult("Unit", "IoError")), func(ctx *Execution, _ []Value) Value {
		close(s.started)
		<-ctx.Context.Done()
		CheckCancelled(ctx)
		return Unit{}
	})
}

func TestLogCloseInterruptsActiveAndQueuedWrites(t *testing.T) {
	ctx := RootExecution()
	output := &logBlockingStream{started: make(chan struct{})}
	transport := newLogTransport(output, nil)
	completed := make(chan Value, 2)
	go func() { completed <- networkingInvoke(ctx, transport, "write", Bytes{Items: []byte("first")}) }()
	select {
	case <-output.started:
	case <-time.After(3 * time.Second):
		t.Fatal("write did not start")
	}
	go func() { completed <- networkingInvoke(ctx, transport, "write", Bytes{Items: []byte("queued")}) }()
	closed := make(chan struct{})
	go func() { networkingInvoke(ctx, transport, "close"); close(closed) }()
	select {
	case <-closed:
	case <-time.After(3 * time.Second):
		t.Fatal("transport close did not interrupt and join writes")
	}
	for i := 0; i < 2; i++ {
		select {
		case result := <-completed:
			libraryFailure(t, result, "Closed")
		case <-time.After(3 * time.Second):
			t.Fatal("admitted write did not return")
		}
	}
}

func TestLogCallerCancellationPreservesTransport(t *testing.T) {
	ctx := RootExecution()
	operationContext, cancel := context.WithCancel(ctx.Context)
	output := &logBlockingStream{started: make(chan struct{})}
	transport := newLogTransport(output, nil)
	defer networkingInvoke(ctx, transport, "close")
	completed := make(chan any, 1)
	go func() {
		defer func() { completed <- recover() }()
		networkingInvoke(inherit(ctx, operationContext), transport, "write", Bytes{Items: []byte("first")})
	}()
	select {
	case <-output.started:
	case <-time.After(3 * time.Second):
		t.Fatal("write did not start")
	}
	cancel()
	select {
	case result := <-completed:
		if _, ok := result.(cancelled); !ok {
			t.Fatalf("lost caller cancellation: %#v", result)
		}
	case <-time.After(3 * time.Second):
		t.Fatal("caller cancellation did not interrupt write")
	}
	// The cancellation only affects this call, leaving the shared transport usable.
	view := transport.(View).Receiver.(*libraryLogTransport)
	view.output = &logTestStream{}
	librarySuccess(t, networkingInvoke(ctx, transport, "write", Bytes{Items: []byte("second")}))
}

type logAcquisitionFile struct {
	cancel context.CancelFunc
	closed bool
}

func (f *logAcquisitionFile) Operation(name string) Function {
	if name == "close" {
		return NewFunction(nil, "Unit", func(*Execution, []Value) Value { f.closed = true; return Unit{} })
	}
	return NewFunction(nil, "@std/WriteStream", func(*Execution, []Value) Value {
		f.cancel()
		return &logTestStream{}
	})
}

type logAcquisitionFS struct{ file *logAcquisitionFile }

func (fs logAcquisitionFS) Operation(name string) Function {
	result := libraryRuntimeType(libraryResult("FileHandle", "FileSystemError"))
	return NewFunction([]string{"path", "flags", "mode"}, result, func(*Execution, []Value) Value {
		return libraryOK(result, fs.file)
	})
}

func TestLogCancelledFileAcquisitionReleasesUndeliveredHandle(t *testing.T) {
	ctx := RootExecution()
	operationContext, cancel := context.WithCancel(ctx.Context)
	defer cancel()
	if err := ctx.Host.initialize(); err != nil {
		t.Fatal(err)
	}
	file := &logAcquisitionFile{cancel: cancel}
	ctx.Host.values["filesystem"] = logAcquisitionFS{file}
	var failure any
	func() {
		defer func() { failure = recover() }()
		StandardFunction("log/file_transport", libraryRuntimeType(libraryResult("Transport", "LogError"))).(Function).Body(inherit(ctx, operationContext), []Value{"events.ndjson"})
	}()
	if _, ok := failure.(cancelled); !ok {
		t.Fatalf("lost acquisition cancellation: %#v", failure)
	}
	if !file.closed {
		t.Fatal("undelivered file handle leaked")
	}
}
