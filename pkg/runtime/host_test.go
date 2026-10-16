package msruntime

import (
	"context"
	"os"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"testing"
	"time"
)

func testCtx(t *testing.T) *Execution {
	t.Helper()
	ctx := RootExecution()
	if err := ctx.State.Host.Initialize(nil); err != nil {
		t.Fatal(err)
	}
	return ctx
}

func mustOK[T, E any](t *testing.T, r Result[T, E]) T {
	t.Helper()
	if r.Failed {
		t.Fatalf("unexpected error: %#v", r.Err)
	}
	return r.Val
}

func wantFSError[T any](t *testing.T, r Result[T, FileSystemError], want FileSystemError) {
	t.Helper()
	if !r.Failed {
		t.Fatalf("expected %#v, got success", want)
	}
	if r.Err != want {
		t.Fatalf("error = %#v, want %#v", r.Err, want)
	}
}

func TestHostRootsAccessors(t *testing.T) {
	ctx := rootExecution(context.Background(), []string{"a", "b"})
	if got := Cli_Arguments(ctx).Items; len(got) != 2 || got[0] != "a" {
		t.Fatalf("arguments %v", got)
	}
	os.Setenv("RT_HOST_TEST", "1")
	if v, _ := Cli_Environment(ctx).Lookup("RT_HOST_TEST"); v != "" {
		t.Fatalf("environment is a startup snapshot, saw %q", v)
	}
	if Io_Stdout(ctx) == nil || Io_Stderr(ctx) == nil || Io_Stdin(ctx) == nil || Io_Files(ctx) == nil || Fs_Filesystem(ctx) == nil || Process_Commands(ctx) == nil || Process_Control(ctx) == nil || System_System(ctx) == nil || Time_Clock(ctx) == nil || Time_WallClock(ctx) == nil {
		t.Fatal("missing root service")
	}
	if ctx.State.Host.Network != nil {
		t.Fatal("network is installed by the network module")
	}
	c := Time_Clock(ctx)
	a, b := c.Now(ctx), c.Now(ctx)
	if Instant_Compare(ctx, a, b) > 0 {
		t.Fatal("clock went backwards")
	}
	other := (&osClock{domain: &ClockDomain{}}).Now(ctx)
	func() {
		defer func() {
			if recover() == nil {
				t.Fatal("instants of different clocks must fault")
			}
		}()
		Instant_Compare(ctx, a, other)
	}()
	ctx.State.Host.Shutdown(ctx)
}

func TestStreamsReadWriteCloseIdempotent(t *testing.T) {
	ctx := testCtx(t)
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	in, out := newHostStream(r, true), newHostStream(w, true)
	mustOK(t, out.Write(ctx, NewBytes([]byte("hello\nworld\n"))))
	mustOK(t, out.Flush(ctx))
	line := mustOK(t, Io_ReadLine(ctx, in, None[int]()))
	if !line.Some || line.Val != "hello" {
		t.Fatalf("line %v", line)
	}
	chunk := mustOK(t, in.Read(ctx, Some(int(3))))
	if string(chunk.Val.Data) != "wor" {
		t.Fatalf("read-ahead chunk %q", chunk.Val.Data)
	}
	out.Close(ctx)
	out.Close(ctx)
	rest := mustOK(t, Io_ReadAll(ctx, in, None[int]()))
	if string(rest.Data) != "ld\n" {
		t.Fatalf("rest %q", rest.Data)
	}
	if res := out.Write(ctx, NewBytes([]byte("x"))); !res.Failed || res.Err != (IoError_Closed{}) {
		t.Fatalf("write after close: %#v", res)
	}
	if res := in.Read(ctx, Some(int(0))); !res.Failed || res.Err != (IoError_InvalidInput{}) {
		t.Fatalf("zero read: %#v", res)
	}
	in.Close(ctx)
	in.Close(ctx)
	if res := in.Read(ctx, None[int]()); !res.Failed || res.Err != (IoError_Closed{}) {
		t.Fatalf("read after close: %#v", res)
	}
}

func TestIoCopyLimit(t *testing.T) {
	ctx := testCtx(t)
	dir := t.TempDir()
	path := filepath.Join(dir, "f")
	os.WriteFile(path, []byte("0123456789"), 0600)
	file := mustOK(t, Io_Files(ctx).Open(ctx, path))
	defer file.Close(ctx)
	dst := filepath.Join(dir, "g")
	g, _ := os.Create(dst)
	sink := newHostStream(g, true)
	res := Io_Copy(ctx, file, sink, Some(int(4)))
	if !res.Failed || res.Err != (IoError_LimitExceeded{}) {
		t.Fatalf("limit: %#v", res)
	}
	sink.Close(ctx)
	if res := Io_Files(ctx).Open(ctx, filepath.Join(dir, "missing")); !res.Failed || res.Err != (IoError_Unavailable{}) {
		t.Fatalf("missing: %#v", res)
	}
	if res := Io_Files(ctx).Open(ctx, "a\x00b"); !res.Failed || res.Err != (IoError_InvalidInput{}) {
		t.Fatalf("nul: %#v", res)
	}
}

func TestFileSystemRemoveProtectedPaths(t *testing.T) {
	ctx := testCtx(t)
	parent := t.TempDir()
	base := filepath.Join(parent, "base")
	if err := os.MkdirAll(filepath.Join(base, "child"), 0700); err != nil {
		t.Fatal(err)
	}
	sentinel := filepath.Join(base, "child", "keep")
	os.WriteFile(sentinel, []byte("untouched"), 0600)
	fs := &osFileSystem{directory: base}
	paths := []string{"", ".", "./", "..", "../", "child/..", "child/../.", "child/.", base, base + "/", base + "/child/..", parent}
	if err := os.Symlink(parent, filepath.Join(base, "alias")); err == nil {
		paths = append(paths, "alias/base", "alias/base/", "alias/base/child/..")
	}
	for _, recursive := range []bool{false, true} {
		for _, path := range paths {
			wantFSError(t, fs.Remove(ctx, path, recursive), FileSystemError_InvalidInput{})
			if data, err := os.ReadFile(sentinel); err != nil || string(data) != "untouched" {
				t.Fatalf("sentinel changed after %q: %q %v", path, data, err)
			}
		}
	}
}

func TestFileSystemRemoveDescendantsAndLinks(t *testing.T) {
	ctx := testCtx(t)
	base := t.TempDir()
	fs := &osFileSystem{directory: base}
	os.MkdirAll(filepath.Join(base, "tree", "child"), 0700)
	os.MkdirAll(filepath.Join(base, " space "), 0700)
	os.WriteFile(filepath.Join(base, "keep"), []byte("keep"), 0600)
	if err := os.Symlink(base, filepath.Join(base, "link")); err == nil {
		mustOK(t, fs.Remove(ctx, "link/", true))
		if _, err := os.Lstat(filepath.Join(base, "link")); !os.IsNotExist(err) {
			t.Fatal("link remains")
		}
	}
	for _, p := range []string{"tree/", " space ", "missing"} {
		mustOK(t, fs.Remove(ctx, p, true))
	}
	if _, err := os.Stat(filepath.Join(base, "keep")); err != nil {
		t.Fatal("followed link")
	}
	mustOK(t, fs.Remove(ctx, "keep", false))
	wantFSError(t, fs.Remove(ctx, "missing", false), FileSystemError_NotFound{})
	os.MkdirAll(filepath.Join(base, "d", "e"), 0700)
	wantFSError(t, fs.Remove(ctx, "d", false), FileSystemError_NotEmpty{})
}

func TestFileSystemEmptyPathsAreInvalid(t *testing.T) {
	ctx := testCtx(t)
	fs := &osFileSystem{directory: t.TempDir()}
	b := NewBytes(nil)
	wantFSError(t, fs.ReadFile(ctx, "", None[int]()), FileSystemError_InvalidInput{})
	wantFSError(t, fs.WriteFile(ctx, "", b, true), FileSystemError_InvalidInput{})
	wantFSError(t, fs.Stat(ctx, "", true), FileSystemError_InvalidInput{})
	wantFSError(t, fs.List(ctx, "", None[int]()), FileSystemError_InvalidInput{})
	wantFSError(t, fs.CreateDirectory(ctx, "", true), FileSystemError_InvalidInput{})
	wantFSError(t, fs.Rename(ctx, "", "x"), FileSystemError_InvalidInput{})
	wantFSError(t, fs.CopyFile(ctx, "a", "", true, None[int]()), FileSystemError_InvalidInput{})
	wantFSError(t, fs.Glob(ctx, "", "*", None[int]()), FileSystemError_InvalidInput{})
	wantFSError(t, fs.Open(ctx, "", "r", 0600), FileSystemError_InvalidInput{})
	wantFSError(t, fs.Open(ctx, "x", "R", 0600), FileSystemError_InvalidInput{})
	wantFSError(t, fs.Watch(ctx, "x", false, 0, None[int]()), FileSystemError_InvalidInput{})
	wantFSError(t, fs.ReadFile(ctx, "x", Some(int(-1))), FileSystemError_InvalidInput{})
	mustOK(t, fs.Stat(ctx, ".", true))
}

func TestFileSystemOperations(t *testing.T) {
	ctx := testCtx(t)
	base := t.TempDir()
	fs := &osFileSystem{directory: base}
	mustOK(t, fs.WriteFile(ctx, "a.txt", NewBytes([]byte("alpha\nbeta\r\n")), false))
	wantFSError(t, fs.WriteFile(ctx, "a.txt", NewBytes(nil), false), FileSystemError_AlreadyExists{})
	if got := mustOK(t, fs.ReadFile(ctx, "a.txt", None[int]())); string(got.Data) != "alpha\nbeta\r\n" {
		t.Fatalf("read %q", got.Data)
	}
	wantFSError(t, fs.ReadFile(ctx, "a.txt", Some(int(3))), FileSystemError_LimitExceeded{})
	wantFSError(t, fs.ReadFile(ctx, ".", None[int]()), FileSystemError_InvalidInput{})
	mustOK(t, fs.AppendFile(ctx, "a.txt", NewBytes([]byte("more"))))
	mustOK(t, fs.CreateDirectory(ctx, "sub/deep", true))
	mustOK(t, fs.CopyFile(ctx, "a.txt", "sub/b.txt", false, None[int]()))
	mustOK(t, fs.CreateLink(ctx, "ln", "a.txt"))
	if target := mustOK(t, fs.ReadLink(ctx, "ln")); target != "a.txt" {
		t.Fatalf("link %q", target)
	}
	info := mustOK(t, fs.Stat(ctx, "a.txt", true))
	if info.Size != 16 || !info.Regular || info.Directory || info.Exact.Len() != 14 {
		t.Fatalf("info %+v", info)
	}
	if info := mustOK(t, fs.Stat(ctx, "ln", false)); !info.Symlink {
		t.Fatal("lstat must see the link")
	}
	entries := mustOK(t, fs.List(ctx, ".", None[int]()))
	var names []string
	for _, e := range entries.Items {
		names = append(names, e.Name)
	}
	if strings.Join(names, ",") != "a.txt,ln,sub" {
		t.Fatalf("names %v", names)
	}
	wantFSError(t, fs.List(ctx, ".", Some(int(1))), FileSystemError_LimitExceeded{})
	globbed := mustOK(t, fs.Glob(ctx, ".", "**/*.txt", None[int]()))
	if strings.Join(globbed.Items, ",") != "a.txt,sub/b.txt" {
		t.Fatalf("glob %v", globbed.Items)
	}
	mustOK(t, fs.CopyTree(ctx, "sub", "sub2", false, None[int](), None[int]()))
	wantFSError(t, fs.CopyTree(ctx, "sub", "sub2", false, None[int](), None[int]()), FileSystemError_AlreadyExists{})
	wantFSError(t, fs.CopyTree(ctx, "sub", "sub/inside", false, None[int](), None[int]()), FileSystemError_InvalidInput{})
	mustOK(t, fs.Rename(ctx, "sub2", "sub3"))
	options := &CopyOptions{Recursive: true, Replace: true, Clone: "none"}
	mustOK(t, fs.Copy(ctx, "sub3", "sub4", options, None[func(*Execution, string, string) bool]()))
	if _, err := os.Stat(filepath.Join(base, "sub4", "b.txt")); err != nil {
		t.Fatal(err)
	}
	options.Clone = "bogus"
	wantFSError(t, fs.Copy(ctx, "sub3", "sub5", options, None[func(*Execution, string, string) bool]()), FileSystemError_InvalidInput{})
	pe := mustOK(t, fs.GlobEntries(ctx, ".", &GlobOptions{Patterns: NewList("**/*.txt"), Exclude: NewList("sub3/**")}, None[func(*Execution, *PathEntry) bool]()))
	var found []string
	for _, e := range pe.Items {
		found = append(found, e.Path)
	}
	if strings.Join(found, ",") != "a.txt,sub/b.txt,sub4/b.txt" {
		t.Fatalf("glob entries %v", found)
	}
	tmp := mustOK(t, fs.Temporary(ctx, "rt-test-"))
	path := tmp.Path(ctx)
	if _, err := os.Stat(path); err != nil {
		t.Fatal(err)
	}
	tmp.Close(ctx)
	tmp.Close(ctx)
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Fatal("temporary directory remains")
	}
	wantFSError(t, fs.Temporary(ctx, "bad/prefix"), FileSystemError_InvalidInput{})
	if runtime.GOOS != "windows" {
		mustOK(t, fs.Chmod(ctx, "a.txt", 0640))
		if info := mustOK(t, fs.Stat(ctx, "a.txt", true)); info.Permissions != 0640 {
			t.Fatalf("mode %o", info.Permissions)
		}
	}
}

func TestFileHandleSemantics(t *testing.T) {
	ctx := testCtx(t)
	base := t.TempDir()
	fs := &osFileSystem{directory: base}
	h := mustOK(t, fs.Open(ctx, "f", "w+", 0600))
	mustOK(t, h.Write(ctx, NewBytes([]byte("line1\nline2\nline3\n"))))
	if n := mustOK(t, h.Seek(ctx, 0, 0)); n != 0 {
		t.Fatal(n)
	}
	lines := mustOK(t, h.ReadLines(ctx, None[int](), None[int]()))
	if strings.Join(lines.Items, "|") != "line1|line2|line3" {
		t.Fatalf("lines %v", lines.Items)
	}
	mustOK(t, h.Seek(ctx, 0, 0))
	wantFSError(t, h.ReadLines(ctx, None[int](), Some(int(2))), FileSystemError_LimitExceeded{})
	mustOK(t, h.Seek(ctx, 0, 0))
	reader := h.Reader(ctx)
	first := mustOK(t, Io_ReadLine(ctx, reader, None[int]()))
	if first.Val != "line1" {
		t.Fatalf("first %q", first.Val)
	}
	// Position-based operations see bytes the line reader read ahead.
	if got := mustOK(t, h.Read(ctx, Some(int(5)))); string(got.Val.Data) != "line2" {
		t.Fatalf("after read-ahead: %q", got.Val.Data)
	}
	if got := mustOK(t, h.ReadAt(ctx, 6, Some(int(5)))); string(got.Data) != "line2" {
		t.Fatalf("read_at %q", got.Data)
	}
	wantFSError(t, h.Seek(ctx, -1, 0), FileSystemError_InvalidInput{})
	h.Close(ctx)
	h.Close(ctx)
	wantFSError(t, h.Sync(ctx), FileSystemError_Closed{})
	if res := reader.Read(ctx, None[int]()); !res.Failed || res.Err != (IoError_Closed{}) {
		t.Fatalf("stream after close: %#v", res)
	}
	ro := mustOK(t, fs.Open(ctx, "f", "r", 0600))
	wantFSError(t, ro.Write(ctx, NewBytes([]byte("x"))), FileSystemError_InvalidInput{})
	ro.Close(ctx)
	wo := mustOK(t, fs.Open(ctx, "f", "a", 0600))
	if res := wo.Reader(ctx).Read(ctx, None[int]()); !res.Failed || res.Err != (IoError_InvalidInput{}) {
		t.Fatalf("write-only read: %#v", res)
	}
	wo.Close(ctx)
}

func TestDirectoryHandle(t *testing.T) {
	ctx := testCtx(t)
	base := t.TempDir()
	os.WriteFile(filepath.Join(base, "x"), nil, 0600)
	fs := &osFileSystem{directory: base}
	d := mustOK(t, fs.OpenDirectory(ctx, "."))
	entry := mustOK(t, d.Read(ctx))
	if !entry.Some || entry.Val.Name != "x" {
		t.Fatalf("entry %+v", entry)
	}
	if end := mustOK(t, d.Read(ctx)); end.Some {
		t.Fatal("expected end")
	}
	d.Close(ctx)
	wantFSError(t, d.Read(ctx), FileSystemError_Closed{})
	wantFSError(t, fs.OpenDirectory(ctx, "x"), FileSystemError_Failed{Message: "not a directory"})
}

func TestPollingWatcher(t *testing.T) {
	ctx := testCtx(t)
	base := t.TempDir()
	fs := &osFileSystem{directory: base}
	w := mustOK(t, fs.Watch(ctx, ".", false, Duration(10*time.Millisecond), None[int]()))
	os.WriteFile(filepath.Join(base, "new"), []byte("x"), 0600)
	events := mustOK(t, w.Next(ctx))
	last := events.Items[len(events.Items)-1]
	if last.Kind != "rename" || !strings.HasSuffix(last.Path, "new") {
		t.Fatalf("events %+v", last)
	}
	w.Close(ctx)
	w.Close(ctx)
	wantFSError(t, w.Next(ctx), FileSystemError_Closed{})
}

func TestNativeWatcher(t *testing.T) {
	ctx := testCtx(t)
	base := t.TempDir()
	fs := &osFileSystem{directory: base}
	w := mustOK(t, fs.WatchNative(ctx, ".", false, None[int](), None[int](), "error"))
	os.WriteFile(filepath.Join(base, "n"), []byte("x"), 0600)
	events := mustOK(t, w.Next(ctx))
	if len(events.Items) != 1 || !strings.HasSuffix(events.Items[0].Path, "n") {
		t.Fatalf("events %+v", events.Items)
	}
	w.Close(ctx)
	wantFSError(t, w.Next(ctx), FileSystemError_Closed{})
	wantFSError(t, fs.WatchNative(ctx, ".", false, None[int](), Some(int(0)), "error"), FileSystemError_InvalidInput{})
	wantFSError(t, fs.WatchNative(ctx, ".", false, None[int](), None[int](), "bogus"), FileSystemError_InvalidInput{})
}

func TestFileSystemCancellation(t *testing.T) {
	ctx := testCtx(t)
	cancel, stop := context.WithCancel(ctx.Context)
	inner := *ctx
	inner.Context = cancel
	stop()
	defer func() {
		if _, ok := recover().(cancelled); !ok {
			t.Fatal("expected cancellation unwind")
		}
	}()
	(&osFileSystem{directory: t.TempDir()}).Glob(&inner, ".", "*", None[int]())
}

func TestTimeOperations(t *testing.T) {
	ctx := testCtx(t)
	ts := mustOK(t, Time_ParseTimestamp(ctx, "2024-02-29T12:30:45.123456789Z"))
	if got := Timestamp_ToString(ctx, ts); got != "2024-02-29T12:30:45.123456789Z" {
		t.Fatal(got)
	}
	if ts.String() != "2024-02-29T12:30:45.123456789Z" {
		t.Fatal(ts.String())
	}
	for _, bad := range []string{"", "2024-02-29", "2024-02-29T12:30:45.1234567891Z", "2024-13-29T12:30:45Z", "0000-01-01T00:00:00Z"} {
		if r := Time_ParseTimestamp(ctx, bad); !r.Failed || r.Err != (TimeError_InvalidData{}) {
			t.Fatalf("%q: %#v", bad, r)
		}
	}
	if r := Time_Timestamp(ctx, 0, 1e9); !r.Failed || r.Err != (TimeError_OutOfRange{}) {
		t.Fatalf("%#v", r)
	}
	shifted := mustOK(t, Timestamp_Shift(ctx, ts, Duration(time.Hour)))
	if d := mustOK(t, Timestamp_Difference(ctx, shifted, ts)); d != Duration(time.Hour) {
		t.Fatal(d)
	}
	if r := Timestamp_Shift(ctx, Timestamp{Seconds: 253402300799}, Duration(time.Hour)); !r.Failed {
		t.Fatal("shift beyond year 9999")
	}
	if Timestamp_Compare(ctx, ts, shifted) != -1 || Timestamp_UnixSeconds(ctx, ts) != int(ts.Seconds) {
		t.Fatal("compare")
	}
	if Duration(5).String() != "5ns" || (Instant{Tick: 7}).String() != "Instant(7)" {
		t.Fatal("format")
	}
	fault := func(f func()) (message string) {
		defer func() { message = recover().(Fault).Message }()
		f()
		return ""
	}
	if m := fault(func() { Duration_Add(ctx, Duration(1<<62), Duration(1<<62)) }); !strings.HasPrefix(m, "Duration.add: overflow; found value (nanoseconds)") {
		t.Fatal(m)
	}
	if m := fault(func() { Duration_Divide(ctx, 1, 0) }); m != "Duration.divide: division by zero; divisor must be nonzero, found 0" {
		t.Fatal(m)
	}
	if m := fault(func() { Sleep(ctx, -1) }); m != "sleep: duration (nanoseconds) must be between 0 and 9223372036854775807, found -1" {
		t.Fatal(m)
	}
	if m := fault(func() { Duration_Negate(ctx, Duration(-1<<63)) }); !strings.HasPrefix(m, "Duration.negate: value (nanoseconds) must be between -9223372036854775807") {
		t.Fatal(m)
	}
	if Duration_ToSeconds(ctx, Duration(1500*time.Millisecond)) != 1.5 || Duration_ToMilliseconds(ctx, Duration(1500*time.Millisecond)) != 1500 {
		t.Fatal("units")
	}
	start := time.Now()
	Sleep(ctx, Duration(5*time.Millisecond))
	if time.Since(start) < 5*time.Millisecond {
		t.Fatal("sleep too short")
	}
}

func TestSystemAndProcessControl(t *testing.T) {
	ctx := testCtx(t)
	sys, control := System_System(ctx), Process_Control(ctx)
	info := sys.Info(ctx)
	if info.CpuCount <= 0 || info.Os == "" {
		t.Fatalf("%+v", info)
	}
	pinfo := mustOK(t, control.Info(ctx))
	if pinfo.Pid <= 0 || pinfo.Os != info.Os {
		t.Fatalf("%+v", pinfo)
	}
	if wd := mustOK(t, control.WorkingDirectory(ctx)); wd != sys.WorkingDirectory(ctx) {
		t.Fatal("working directory")
	}
	if e := System_Endianness(ctx); e != "LE" && e != "BE" {
		t.Fatal(e)
	}
	if System_OsType(ctx) == "" || System_DevNull(ctx) == "" || System_Constants(ctx).Len() == 0 || Fs_Constants(ctx).Len() == 0 {
		t.Fatal("system constants")
	}
	name := "RT_CONFORMANCE"
	mustOK(t, control.SetEnvironment(ctx, name, Some("v")))
	if v := sys.Environment(ctx, name); !v.Some || v.Val != "v" {
		t.Fatal("system environment")
	}
	if v, _ := mustOK(t, control.Environment(ctx)).Lookup(name); v != "v" {
		t.Fatal("process environment")
	}
	mustOK(t, control.SetEnvironment(ctx, name, None[string]()))
	if sys.Environment(ctx, name).Some {
		t.Fatal("unset")
	}
	if r := control.SetEnvironment(ctx, "A=B", None[string]()); !r.Failed || r.Err != (ProcessError_InvalidInput{}) {
		t.Fatalf("%#v", r)
	}
	before := mustOK(t, control.Uptime(ctx))
	reading := Duration(control.MonotonicTime(ctx))
	after := mustOK(t, control.Uptime(ctx))
	if reading < before || reading > after {
		t.Fatal("monotonic origin")
	}
	if r := control.WatchSignals(ctx, NewList[int](), None[int]()); !r.Failed {
		t.Fatal("empty signal list")
	}
	if r := control.Umask(ctx, 01000); !r.Failed {
		t.Fatal("umask range")
	}
}

func TestLoadEnvironment(t *testing.T) {
	ctx := testCtx(t)
	path := filepath.Join(t.TempDir(), ".env")
	os.WriteFile(path, []byte("# c\nexport RT_LOAD_A=one\nRT_LOAD_B=\"two words\" # trailing\nRT_LOAD_C=3 # note\n"), 0600)
	t.Setenv("RT_LOAD_C", "keep")
	mustOK(t, Process_Control(ctx).LoadEnvironment(ctx, path, None[int]()))
	if os.Getenv("RT_LOAD_A") != "one" || os.Getenv("RT_LOAD_B") != "two words" || os.Getenv("RT_LOAD_C") != "keep" {
		t.Fatal("environment loading")
	}
	os.Unsetenv("RT_LOAD_A")
	os.Unsetenv("RT_LOAD_B")
	bad := filepath.Join(t.TempDir(), "bad")
	os.WriteFile(bad, []byte("1BAD=x\n"), 0600)
	if r := Process_Control(ctx).LoadEnvironment(ctx, bad, None[int]()); !r.Failed || r.Err != (ProcessError_InvalidData{}) {
		t.Fatalf("%#v", r)
	}
}

func TestCommands(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("posix tools")
	}
	ctx := testCtx(t)
	commands := Process_Commands(ctx)
	run := func(program string, args []string, input string, max Option[int], timeout Option[Duration]) Result[*CommandOutput, CommandError] {
		return commands.Run(ctx, program, NewList(args...), NewBytes([]byte(input)), max, timeout)
	}
	if r := run("", nil, "", None[int](), None[Duration]()); !r.Failed || r.Err != (CommandError_InvalidInput{}) {
		t.Fatalf("%#v", r)
	}
	if r := run("rt-nonexistent-command", nil, "", None[int](), None[Duration]()); !r.Failed || r.Err != (CommandError_Unavailable{}) {
		t.Fatalf("%#v", r)
	}
	out := mustOK(t, run("sh", []string{"-c", "cat; echo err >&2; exit 3"}, "in", None[int](), None[Duration]()))
	if out.ExitCode != 3 || string(out.Stdout.Data) != "in" || string(out.Stderr.Data) != "err\n" {
		t.Fatalf("%+v", out)
	}
	if r := run("sh", []string{"-c", "echo 0123456789"}, "", Some(int(4)), None[Duration]()); !r.Failed || r.Err != (CommandError_OutputLimit{}) {
		t.Fatalf("%#v", r)
	}
	if r := run("sleep", []string{"5"}, "", None[int](), Some(Duration(50*time.Millisecond))); !r.Failed || r.Err != (CommandError_Timeout{}) {
		t.Fatalf("%#v", r)
	}
	if r := run("true", nil, "", Some(int(-1)), None[Duration]()); !r.Failed || r.Err != (CommandError_InvalidInput{}) {
		t.Fatalf("%#v", r)
	}
}

func TestSubprocessStreamsAndCleanup(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("posix tools")
	}
	ctx := testCtx(t)
	child := mustOK(t, Process_Commands(ctx).Spawn(ctx, "cat", NewList[string]()))
	mustOK(t, child.Stdin(ctx).Write(ctx, NewBytes([]byte("ping\n"))))
	line := mustOK(t, Io_ReadLine(ctx, child.Stdout(ctx), None[int]()))
	if line.Val != "ping" {
		t.Fatal(line)
	}
	child.Stdin(ctx).Close(ctx)
	if code := mustOK(t, child.Wait(ctx, None[Duration]())); code != 0 {
		t.Fatal(code)
	}
	if eof := mustOK(t, child.Stdout(ctx).Read(ctx, None[int]())); eof.Some {
		t.Fatal("expected eof")
	}
	child.Close(ctx)
	child.Close(ctx)

	sleeper := mustOK(t, Process_Commands(ctx).Spawn(ctx, "sleep", NewList("30")))
	if r := sleeper.Wait(ctx, Some(Duration(20*time.Millisecond))); !r.Failed || r.Err != (CommandError_Timeout{}) {
		t.Fatalf("%#v", r)
	}
	sleeper.Close(ctx)
	if r := Process_Commands(ctx).Spawn(ctx, "rt-nonexistent-command", NewList[string]()); !r.Failed || r.Err != (CommandError_Unavailable{}) {
		t.Fatalf("%#v", r)
	}
}

type captureStream struct {
	data   []byte
	closed bool
}

func (c *captureStream) Close(*Execution) Unit { c.closed = true; return Unit{} }
func (c *captureStream) Flush(*Execution) Result[Unit, IoError] {
	return Ok[Unit, IoError](Unit{})
}
func (c *captureStream) Write(_ *Execution, b *Bytes) Result[Unit, IoError] {
	c.data = append(c.data, b.Data...)
	return Ok[Unit, IoError](Unit{})
}

func TestLogger(t *testing.T) {
	ctx := testCtx(t)
	sink := &captureStream{}
	transport := Log_StreamTransport(ctx, sink)
	base := mustOK(t, Log_Create(ctx, transport, Some[LogLevel](LogLevel_Info{}), Some(false), None[int]()))
	enc := func(s *JsonScope, v map[string]int) (JsonValue, bool) {
		out := NewMap[string, JsonValue]()
		for k, n := range v {
			out.Put(k, JsonValue_NumberValue{Text: strconv.Itoa(n)})
		}
		return JsonValue_ObjectValue{Values: out}, true
	}
	logger := mustOK(t, Log_Bind(ctx, JsonEncString, base, "demo"))
	if string(sink.data) != "" {
		t.Fatal("bind writes nothing")
	}
	if r := logger.Debug(ctx, "hidden"); r.Failed || len(sink.data) != 0 {
		t.Fatal("debug below threshold")
	}
	mustOK(t, Log_Record(ctx, enc, logger, LogLevel_Warn{}, "careful \"x\"", map[string]int{"n": 5}))
	if got, want := string(sink.data), `{"level":40,"msg":"careful \"x\"","data":"demo","n":5}`+"\n"; got != want {
		t.Fatalf("record %q want %q", got, want)
	}
	sink.data = nil
	mustOK(t, Log_Record(ctx, JsonEncInt, base, LogLevel_Info{}, "scalar", 7))
	if got, want := string(sink.data), `{"level":30,"msg":"scalar","data":7}`+"\n"; got != want {
		t.Fatalf("record %q want %q", got, want)
	}
	sink.data = nil
	mustOK(t, Log_Record(ctx, enc, base, LogLevel_Info{}, "reserved", map[string]int{"msg": 1, "level": 2}))
	if got, want := string(sink.data), `{"level":30,"msg":"reserved"}`+"\n"; got != want {
		t.Fatalf("record %q want %q", got, want)
	}
	if r := base.LogJson(ctx, LogLevel_Info{}, "bad", "{"); !r.Failed || r.Err != (LogError_InvalidData{}) {
		t.Fatalf("%#v", r)
	}
	if !logger.Enabled(ctx, LogLevel_Error{}) || logger.Enabled(ctx, LogLevel_Trace{}) || logger.Enabled(ctx, LogLevel_Silent{}) {
		t.Fatal("enabled")
	}
	logger.SetLevel(ctx, LogLevel_Silent{})
	if _, ok := logger.Level(ctx).(LogLevel_Silent); !ok {
		t.Fatal("level")
	}
	if r := logger.Log(ctx, LogLevel_Silent{}, "x"); !r.Failed || r.Err != (LogError_InvalidInput{}) {
		t.Fatalf("%#v", r)
	}
	if r := Log_Record(ctx, JsonEncInt, logger, LogLevel_Silent{}, "x", 1); !r.Failed || r.Err != (LogError_InvalidInput{}) {
		t.Fatalf("%#v", r)
	}
	child := mustOK(t, Log_Bind(ctx, JsonEncInt, logger, 1))
	if _, ok := child.Level(ctx).(LogLevel_Silent); !ok {
		t.Fatal("child level")
	}
	mustOK(t, logger.Flush(ctx))
	limited := mustOK(t, Log_Create(ctx, transport, None[LogLevel](), Some(false), Some(int(10))))
	if r := limited.Info(ctx, "this message is far too long"); !r.Failed || r.Err != (LogError_LimitExceeded{}) {
		t.Fatalf("%#v", r)
	}
	if r := Log_Create(ctx, transport, None[LogLevel](), None[bool](), Some(int(-1))); !r.Failed {
		t.Fatal("negative budget")
	}
	transport.Close(ctx)
	transport.Close(ctx)
	if sink.closed {
		t.Fatal("borrowed stream must stay open")
	}
	if r := child.Flush(ctx); !r.Failed || r.Err != (LogError_Closed{}) {
		t.Fatalf("%#v", r)
	}
}

func TestFileTransport(t *testing.T) {
	ctx := testCtx(t)
	path := filepath.Join(t.TempDir(), "log.jsonl")
	transport := mustOK(t, Log_FileTransport(ctx, path))
	logger := mustOK(t, Log_Create(ctx, transport, None[LogLevel](), Some(false), None[int]()))
	mustOK(t, logger.Info(ctx, "one"))
	transport.Close(ctx)
	data, err := os.ReadFile(path)
	if err != nil || string(data) != `{"level":30,"msg":"one"}`+"\n" {
		t.Fatalf("%q %v", data, err)
	}
	bad := Log_FileTransport(ctx, filepath.Join(t.TempDir(), "missing", "x"))
	if !bad.Failed {
		t.Fatal("expected error")
	}
	if c, ok := bad.Err.(LogError_FileSystem); !ok || c.Cause != (FileSystemError_NotFound{}) {
		t.Fatalf("%#v", bad.Err)
	}
	if Errors_Message_LogError(ctx, bad.Err) != "filesystem: file or directory not found" {
		t.Fatal(Errors_Message_LogError(ctx, bad.Err))
	}
}

func TestHostErrorMessages(t *testing.T) {
	ctx := testCtx(t)
	cases := []struct{ got, want string }{
		{Errors_Message_IoError(ctx, IoError_Failed{Message: "secret path /x"}), "secret path /x"},
		{Errors_Message_IoError(ctx, IoError_Unavailable{}), "I/O: service unavailable"},
		{Errors_Message_IoError(ctx, IoError_LimitExceeded{}), "I/O: limit exceeded"},
		{Errors_Message_FileSystemError(ctx, FileSystemError_NotFound{}), "filesystem: file or directory not found"},
		{Errors_Message_FileSystemError(ctx, FileSystemError_NotEmpty{}), "filesystem: directory not empty"},
		{Errors_Message_SystemError(ctx, SystemError_PermissionDenied{}), "system: permission denied"},
		{Errors_Message_ProcessError(ctx, ProcessError_Unsupported{}), "process: operation not supported"},
		{Errors_Message_CommandError(ctx, CommandError_OutputLimit{}), "command: output limit exceeded"},
		{Errors_Message_CommandError(ctx, CommandError_Timeout{}), "command: operation timed out"},
		{Errors_Message_TimeError(ctx, TimeError_OutOfRange{}), "time: value out of range"},
		{Errors_Message_LogError(ctx, LogError_Io{Cause: IoError_Closed{}}), "I/O: resource is closed"},
		{Errors_Message_LogError(ctx, LogError_Closed{}), "logging: resource is closed"},
		{Errors_Message_TextError(ctx, TextError_Text{Message: "verbatim"}), "verbatim"},
		{Errors_Message_MissingValue(ctx, MissingValue_Missing{Location: "a.ms:3"}), "missing value at a.ms:3"},
		{Errors_Message_JsonError(ctx, JsonError_InvalidData{}), "JSON: invalid data"},
		{Errors_Message_ExecutionError(ctx, ExecutionError_Crashed{Message: "boom"}), "boom"},
		{Errors_Message_ExecutionError(ctx, ExecutionError_Cancelled{}), "task execution: operation cancelled"},
	}
	for _, c := range cases {
		if c.got != c.want {
			t.Errorf("got %q want %q", c.got, c.want)
		}
	}
}

// directError lets the tests classify a bare case through the Error contract.
type viewOf struct{ self FileSystemError }

func (v viewOf) Message(ctx *Execution) string { return Errors_Message_FileSystemError(ctx, v.self) }

type plainError struct{}

func (plainError) Message(*Execution) string { return "filesystem: file or directory not found" }

func TestErrorCategory(t *testing.T) {
	ctx := testCtx(t)
	category := func(e Error) Option[ErrorCategory] { return Errors_Category(ctx, e) }
	if c := category(viewOf{FileSystemError_NotFound{}}); !c.Some || c.Val != (ErrorCategory_NotFound{}) {
		t.Fatalf("view: %#v", c)
	}
	if c := category(viewOf{FileSystemError_Failed{Message: "x"}}); c.Some {
		t.Fatalf("failed has no category: %#v", c)
	}
	if c := category(viewOf{FileSystemError_NotEmpty{}}); c.Some {
		t.Fatal("NotEmpty has no shared category")
	}
	if category(plainError{}).Some {
		t.Fatal("messages are never parsed")
	}
	if category(nil).Some {
		t.Fatal("nil")
	}
	direct := []struct {
		e    Categorized
		want ErrorCategory
	}{
		{IoError_Unavailable{}, ErrorCategory_Unavailable{}},
		{CommandError_Timeout{}, ErrorCategory_Timeout{}},
		{ProcessError_NotFound{}, ErrorCategory_NotFound{}},
		{SystemError_AlreadyExists{}, ErrorCategory_AlreadyExists{}},
		{JsonError_InvalidData{}, ErrorCategory_InvalidData{}},
		{ExecutionError_Timeout{}, ErrorCategory_Timeout{}},
	}
	for _, d := range direct {
		if d.e.Category() != d.want {
			t.Errorf("%T", d.e)
		}
	}
	if _, ok := any(IoError_Failed{}).(Categorized); ok {
		t.Fatal("Failed has no category")
	}
	if _, ok := any(CommandError_OutputLimit{}).(Categorized); ok {
		t.Fatal("OutputLimit has no category")
	}
}

func (v viewOf) Receiver() any { return v.self }
