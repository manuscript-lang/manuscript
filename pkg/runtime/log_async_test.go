package msruntime

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func asyncLogger(t *testing.T, path string, maxBytes Option[int], maxAge Option[Duration], maxFiles Option[int], queue Option[int]) (Logger, Transport) {
	t.Helper()
	ctx := testCtx(t)
	transport := mustOK(t, Log_AsyncFileTransport(ctx, path, maxBytes, maxAge, maxFiles, queue))
	return mustOK(t, Log_Create(ctx, transport, None[LogLevel](), Some(false), None[int]())), transport
}

func TestAsyncFileTransportWritesAndFlushes(t *testing.T) {
	ctx := testCtx(t)
	path := filepath.Join(t.TempDir(), "log.jsonl")
	logger, transport := asyncLogger(t, path, None[int](), None[Duration](), None[int](), None[int]())
	mustOK(t, logger.Info(ctx, "one"))
	mustOK(t, logger.Info(ctx, "two"))
	mustOK(t, logger.Flush(ctx))
	data, _ := os.ReadFile(path)
	if string(data) != `{"level":30,"msg":"one"}`+"\n"+`{"level":30,"msg":"two"}`+"\n" {
		t.Fatalf("%q", data)
	}
	mustOK(t, logger.Info(ctx, "three"))
	transport.Close(ctx)
	data, _ = os.ReadFile(path)
	if !strings.HasSuffix(string(data), `"three"}`+"\n") {
		t.Fatalf("close must drain accepted records: %q", data)
	}
	if r := transport.Write(ctx, NewBytes([]byte("x"))); !r.Failed || r.Err != (LogError_Closed{}) {
		t.Fatalf("%#v", r)
	}
	transport.Close(ctx)
}

func TestAsyncFileTransportRotatesBySizeAndCountsFiles(t *testing.T) {
	ctx := testCtx(t)
	path := filepath.Join(t.TempDir(), "log.jsonl")
	record := len(`{"level":30,"msg":"m0"}` + "\n")
	logger, transport := asyncLogger(t, path, Some(record*2), None[Duration](), Some(3), None[int]())
	for i := 0; i < 10; i++ {
		mustOK(t, logger.Info(ctx, fmt.Sprintf("m%d", i)))
	}
	transport.Close(ctx)
	read := func(name string) string {
		data, err := os.ReadFile(name)
		if err != nil {
			t.Fatal(err)
		}
		return string(data)
	}
	want := map[string]string{
		path:        `{"level":30,"msg":"m8"}` + "\n" + `{"level":30,"msg":"m9"}` + "\n",
		path + ".1": `{"level":30,"msg":"m6"}` + "\n" + `{"level":30,"msg":"m7"}` + "\n",
		path + ".2": `{"level":30,"msg":"m4"}` + "\n" + `{"level":30,"msg":"m5"}` + "\n",
	}
	for name, content := range want {
		if got := read(name); got != content {
			t.Fatalf("%s: %q", name, got)
		}
	}
	if _, err := os.Stat(path + ".3"); !os.IsNotExist(err) {
		t.Fatalf("file beyond max_files kept: %v", err)
	}
}

func TestAsyncFileTransportSingleFileTruncates(t *testing.T) {
	ctx := testCtx(t)
	path := filepath.Join(t.TempDir(), "log.jsonl")
	logger, transport := asyncLogger(t, path, Some(10), None[Duration](), Some(1), None[int]())
	mustOK(t, logger.Info(ctx, "a"))
	mustOK(t, logger.Info(ctx, "b"))
	transport.Close(ctx)
	data, _ := os.ReadFile(path)
	if string(data) != `{"level":30,"msg":"b"}`+"\n" {
		t.Fatalf("%q", data)
	}
	if _, err := os.Stat(path + ".1"); !os.IsNotExist(err) {
		t.Fatal("rotated file kept")
	}
}

func TestAsyncFileTransportRotatesByAge(t *testing.T) {
	ctx := testCtx(t)
	path := filepath.Join(t.TempDir(), "log.jsonl")
	logger, transport := asyncLogger(t, path, None[int](), Some(Duration(50*time.Millisecond)), None[int](), None[int]())
	mustOK(t, logger.Info(ctx, "old"))
	mustOK(t, logger.Flush(ctx))
	time.Sleep(80 * time.Millisecond)
	mustOK(t, logger.Info(ctx, "new"))
	transport.Close(ctx)
	old, _ := os.ReadFile(path + ".1")
	current, _ := os.ReadFile(path)
	if string(old) != `{"level":30,"msg":"old"}`+"\n" || string(current) != `{"level":30,"msg":"new"}`+"\n" {
		t.Fatalf("%q %q", old, current)
	}
}

func TestAsyncFileTransportResumesExistingFileSize(t *testing.T) {
	ctx := testCtx(t)
	path := filepath.Join(t.TempDir(), "log.jsonl")
	os.WriteFile(path, []byte(strings.Repeat("x", 30)), 0600)
	logger, transport := asyncLogger(t, path, Some(40), None[Duration](), None[int](), None[int]())
	mustOK(t, logger.Info(ctx, "a"))
	transport.Close(ctx)
	old, _ := os.ReadFile(path + ".1")
	if string(old) != strings.Repeat("x", 30) {
		t.Fatalf("%q", old)
	}
}

func TestAsyncFileTransportQueueFullDoesNotBlock(t *testing.T) {
	ctx := testCtx(t)
	transport := mustOK(t, Log_AsyncFileTransport(ctx, filepath.Join(t.TempDir(), "log.jsonl"), None[int](), None[Duration](), None[int](), Some(1)))
	impl := transport.(*asyncFileTransport)
	// Hold the writer by filling the queue faster than it drains.
	full := false
	deadline := time.After(5 * time.Second)
	for !full {
		select {
		case <-deadline:
			t.Fatal("queue never reported full")
		default:
		}
		r := impl.Write(ctx, NewBytes([]byte("x\n")))
		if r.Failed {
			if r.Err != (LogError_LimitExceeded{}) {
				t.Fatalf("%#v", r.Err)
			}
			full = true
		}
	}
	transport.Close(ctx)
}

func TestAsyncFileTransportValidationAndErrors(t *testing.T) {
	ctx := testCtx(t)
	dir := t.TempDir()
	path := filepath.Join(dir, "log.jsonl")
	for name, call := range map[string]func() Result[Transport, LogError]{
		"max_bytes": func() Result[Transport, LogError] {
			return Log_AsyncFileTransport(ctx, path, Some(0), None[Duration](), None[int](), None[int]())
		},
		"max_age": func() Result[Transport, LogError] {
			return Log_AsyncFileTransport(ctx, path, None[int](), Some(Duration(0)), None[int](), None[int]())
		},
		"max_files": func() Result[Transport, LogError] {
			return Log_AsyncFileTransport(ctx, path, None[int](), None[Duration](), Some(-1), None[int]())
		},
		"queue_size": func() Result[Transport, LogError] {
			return Log_AsyncFileTransport(ctx, path, None[int](), None[Duration](), None[int](), Some(0))
		},
	} {
		if r := call(); !r.Failed || r.Err != (LogError_InvalidInput{}) {
			t.Fatalf("%s: %#v", name, r)
		}
	}
	bad := Log_AsyncFileTransport(ctx, filepath.Join(dir, "missing", "x"), None[int](), None[Duration](), None[int](), None[int]())
	if c, ok := bad.Err.(LogError_FileSystem); !bad.Failed || !ok || c.Cause != (FileSystemError_NotFound{}) {
		t.Fatalf("%#v", bad)
	}
}

func TestAsyncFileTransportReportsRotationFailureOnNextWrite(t *testing.T) {
	ctx := testCtx(t)
	dir := t.TempDir()
	path := filepath.Join(dir, "log.jsonl")
	logger, transport := asyncLogger(t, path, Some(10), None[Duration](), Some(2), None[int]())
	mustOK(t, logger.Info(ctx, "a"))
	mustOK(t, logger.Flush(ctx))
	// Make the rotation target a non-empty directory so the removal of the oldest file fails.
	os.MkdirAll(filepath.Join(dir, "log.jsonl.1", "child"), 0700)
	mustOK(t, logger.Info(ctx, "b"))
	r := logger.Flush(ctx)
	if !r.Failed {
		t.Fatalf("expected the rotation failure to surface: %#v", r)
	}
	transport.Close(ctx)
}
