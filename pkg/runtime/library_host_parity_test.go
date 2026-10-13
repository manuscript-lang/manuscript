package msruntime

import (
	"context"
	"encoding/json"
	"github.com/manuscript-lang/manuscript/internal/hostos"
	"os"
	"path/filepath"
	goruntime "runtime"
	"testing"
	"time"
)

func TestNodePathFixtures(t *testing.T) {
	data, err := os.ReadFile("testdata/node-path.json")
	if err != nil {
		t.Fatal(err)
	}
	var cases []struct {
		Dialect, Name string
		Args          []json.RawMessage
		Expected      json.RawMessage
	}
	if err = json.Unmarshal(data, &cases); err != nil {
		t.Fatal(err)
	}
	for _, c := range cases {
		t.Run(c.Dialect+"/"+c.Name+"/"+string(c.Args[0]), func(t *testing.T) {
			p := libraryPaths{c.Dialect == "win32"}
			name := c.Name
			switch name {
			case "extname":
				name = "extension"
			case "isAbsolute":
				name = "is_absolute"
			case "matchesGlob":
				name = "matches_glob"
			case "toNamespacedPath":
				name = "to_namespaced_path"
			}
			var args []Value
			for _, raw := range c.Args {
				var value any
				if err = json.Unmarshal(raw, &value); err != nil {
					t.Fatal(err)
				}
				switch v := value.(type) {
				case string:
					args = append(args, v)
				case map[string]any:
					fields := map[string]Value{}
					for key, field := range v {
						if key == "dir" {
							key = "directory"
						}
						if key == "ext" {
							key = "extension"
						}
						fields[key] = field
					}
					args = append(args, Record{"@std/PathParts", fields})
				case []any:
					var parts []string
					for _, s := range v {
						parts = append(parts, s.(string))
					}
					args = append(args, libraryStrings(parts))
				}
			}
			value := p.call(RootExecution(), libraryRuntimeType(libraryResult("String", "FileSystemError")), name, args)
			if name == "resolve" || name == "relative" || name == "matches_glob" {
				value = librarySuccess(t, value)
			}
			if name == "parse" {
				f := value.(Record).Fields
				value = map[string]Value{"root": f["root"], "dir": f["directory"], "base": f["base"], "ext": f["extension"], "name": f["name"]}
			}
			got, _ := json.Marshal(value)
			var actual, expected any
			json.Unmarshal(got, &actual)
			json.Unmarshal(c.Expected, &expected)
			actualJSON, _ := json.Marshal(actual)
			expectedJSON, _ := json.Marshal(expected)
			if string(actualJSON) != string(expectedJSON) {
				t.Errorf("got %s, Node.js expected %s", got, c.Expected)
			}
		})
	}
}
func TestPathResolveRequiresExplicitDriveBase(t *testing.T) {
	paths := libraryPaths{windows: true}
	if _, ok := paths.resolve(`C:\base`, []string{`D:relative`}); ok {
		t.Fatal("drive-relative resolution consulted an unknown drive base")
	}
	if value, ok := paths.resolve(`C:\base`, []string{`D:relative`, `C:\final`}); !ok || value != `C:\final` {
		t.Fatal("superseded drive-relative component rejected", value, ok)
	}
}

func TestExpandedFileHandles(t *testing.T) {
	ctx := RootExecution()
	fs := &libraryFileSystem{t.TempDir()}
	call := func(name string, a ...Value) Value { return fs.Operation(name).Body(ctx, a) }
	h := librarySuccess(t, call("open", "file", "wx+", int64(0600)))
	op := func(name string, a ...Value) Value {
		return Invoke(ctx, Bind(h, "", name), func() []Argument {
			var args []Argument
			for _, v := range a {
				args = append(args, Argument{Name: Bind(h, "", name).(Function).Labels[len(args)], Value: v})
			}
			return args
		}())
	}
	defer op("close")
	librarySuccess(t, op("write_file", Bytes{[]byte("hello\r\nworld\n")}))
	libraryFailure(t, call("open", "file", "wx", int64(0600)), "AlreadyExists")
	if got := librarySuccess(t, op("read_at", int64(0), int64(5))).(Bytes); string(got.Items) != "hello" {
		t.Fatal(got)
	}
	librarySuccess(t, op("write_at", int64(0), Bytes{[]byte("HELLO")}))
	librarySuccess(t, op("seek", int64(0), int64(0)))
	lines := librarySuccess(t, op("read_lines", int64(64), int64(2))).(*List)
	if len(lines.Items) != 2 || lines.Items[0] != "HELLO" || lines.Items[1] != "world" {
		t.Fatal(lines)
	}
	librarySuccess(t, op("seek", int64(0), int64(0)))
	libraryFailure(t, op("read_file", int64(2)), "LimitExceeded")
	librarySuccess(t, op("seek", int64(0), int64(0)))
	vectors := librarySuccess(t, op("read_vectors", libraryList("Int", []Value{int64(2), int64(3)}), int64(0))).(*List)
	if string(vectors.Items[0].(Bytes).Items) != "HE" || string(vectors.Items[1].(Bytes).Items) != "LLO" {
		t.Fatal(vectors)
	}
	librarySuccess(t, op("write_vectors", libraryList("@std/Bytes", []Value{Bytes{[]byte("ab")}, Bytes{[]byte("cd")}}), int64(0)))
	librarySuccess(t, op("truncate", int64(4)))
	librarySuccess(t, op("sync"))
	librarySuccess(t, op("data_sync"))
	info := librarySuccess(t, op("stat")).(Record).Fields
	if info["size"] != int64(4) || info["regular"] != true {
		t.Fatal(info)
	}
	libraryFailure(t, op("read_at", int64(-1), int64(5)), "InvalidInput")
	libraryFailure(t, op("seek", int64(0), int64(3)), "InvalidInput")
	op("close")
	op("close")
	libraryFailure(t, op("stat"), "Closed")
}
func TestExpandedFileSystem(t *testing.T) {
	ctx := RootExecution()
	directory := t.TempDir()
	fs := &libraryFileSystem{directory}
	call := func(name string, a ...Value) Value { return fs.Operation(name).Body(ctx, a) }
	librarySuccess(t, call("create_directory", "source/sub", true))
	librarySuccess(t, call("write_file", "source/sub/a.txt", Bytes{[]byte("data")}, false))
	librarySuccess(t, call("append_file", "source/sub/a.txt", Bytes{[]byte("!")}))
	librarySuccess(t, call("access", "source/sub/a.txt", int64(4)))
	libraryFailure(t, call("copy_tree", "source", "source/copy", true, int64(10), int64(100)), "InvalidInput")
	libraryFailure(t, call("copy_tree", "source", "limited", false, int64(10), int64(4)), "LimitExceeded")
	librarySuccess(t, call("copy_tree", "source", "copy", false, int64(3), int64(5)))
	matches := librarySuccess(t, call("glob", "copy", "**/*.txt", int64(1))).(*List)
	if len(matches.Items) != 1 || matches.Items[0] != filepath.Join("sub", "a.txt") {
		t.Fatal(matches)
	}
	libraryFailure(t, call("glob", "copy", "[", int64(1)), "InvalidInput")
	libraryFailure(t, call("glob", "copy", "**/*.txt", int64(0)), "LimitExceeded")
	d := librarySuccess(t, call("open_directory", "copy/sub"))
	read := func() Value { return Invoke(ctx, Bind(d, "", "read"), nil) }
	if librarySuccess(t, read()).(Alternative).Tag != "some" {
		t.Fatal("missing entry")
	}
	if librarySuccess(t, read()).(Alternative).Tag != "none" {
		t.Fatal("missing EOF")
	}
	Invoke(ctx, Bind(d, "", "close"), nil)
	libraryFailure(t, read(), "Closed")
	temp := librarySuccess(t, call("temporary", "manuscript-test-"))
	path := Invoke(ctx, Bind(temp, "", "path"), nil).(string)
	if _, err := os.Stat(path); err != nil {
		t.Fatal(err)
	}
	Invoke(ctx, Bind(temp, "", "close"), nil)
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Fatal("temporary directory retained", err)
	}
	librarySuccess(t, call("truncate", "copy/sub/a.txt", int64(2)))
	if goruntime.GOOS != "windows" {
		librarySuccess(t, call("chmod", "copy/sub/a.txt", int64(0400)))
		stat := librarySuccess(t, call("stat_filesystem", "copy")).(Record)
		if stat.Fields["block_size"].(int64) <= 0 {
			t.Fatal(stat)
		}
	}
}
func TestExpandedWatcherCloseAndChanges(t *testing.T) {
	ctx := RootExecution()
	directory := t.TempDir()
	fs := &libraryFileSystem{directory}
	w := librarySuccess(t, fs.Operation("watch").Body(ctx, []Value{".", true, Duration(time.Millisecond), int64(10)}))
	next := func(ctx *Execution) Value { return Invoke(ctx, Bind(w, "", "next"), nil) }
	if err := os.WriteFile(filepath.Join(directory, "added"), []byte("hello"), 0600); err != nil {
		t.Fatal(err)
	}
	lifetime, cancel := context.WithTimeout(ctx.Context, time.Second)
	defer cancel()
	limited := *ctx
	limited.Context = lifetime
	changes := librarySuccess(t, next(&limited)).(*List)
	found := false
	for _, v := range changes.Items {
		if v.(Record).Fields["path"] == filepath.Join(directory, "added") {
			found = true
		}
	}
	if !found {
		t.Fatal(changes)
	}
	done := make(chan Value, 1)
	go func() { done <- next(ctx) }()
	Invoke(ctx, Bind(w, "", "close"), nil)
	select {
	case v := <-done:
		libraryFailure(t, v, "Closed")
	case <-time.After(time.Second):
		t.Fatal("watch close did not join")
	}
}
func TestExpandedSystemAndProcess(t *testing.T) {
	ctx := RootExecution()
	system := &librarySystem{}
	control := libraryProcessControl{}
	for _, name := range []string{"hostname", "home_directory", "temporary_directory", "user_info", "network_interfaces", "machine"} {
		librarySuccess(t, system.Operation(name).Body(ctx, nil))
	}
	for _, name := range []string{"info", "memory_usage", "uptime", "environment"} {
		librarySuccess(t, control.Operation(name).Body(ctx, nil))
	}
	if goruntime.GOOS == "windows" {
		libraryFailure(t, control.Operation("groups").Body(ctx, nil), "Unsupported")
	} else {
		librarySuccess(t, control.Operation("groups").Body(ctx, nil))
	}
	{
		for _, name := range []string{"constrained_memory", "available_memory", "title"} {
			librarySuccess(t, control.Operation(name).Body(ctx, nil))
		}
		for _, name := range []string{"cpus", "metrics", "os_release", "os_version"} {
			librarySuccess(t, system.Operation(name).Body(ctx, nil))
		}
		for _, name := range []string{"cpu_usage", "resource_usage"} {
			librarySuccess(t, control.Operation(name).Body(ctx, nil))
		}
	}
	key := "MANUSCRIPT_STDLIB_TEST_ENV"
	t.Setenv(key, "original")
	librarySuccess(t, control.Operation("set_environment").Body(ctx, []Value{key, optional("String", "updated", true)}))
	if os.Getenv(key) != "updated" {
		t.Fatal("environment not set")
	}
	librarySuccess(t, control.Operation("set_environment").Body(ctx, []Value{key, optional("String", nil, false)}))
	if _, ok := os.LookupEnv(key); ok {
		t.Fatal("environment not unset")
	}
	libraryFailure(t, control.Operation("set_environment").Body(ctx, []Value{"BAD=KEY", optional("String", "value", true)}), "InvalidInput")
	entries, ok := libraryParseEnvironment("export FIRST=one # comment\nSECOND='two\nlines'\nTHIRD=\"three\"\n")
	if !ok || len(entries) != 3 || entries[1].Value != "two\nlines" {
		t.Fatal(entries, ok)
	}
	if _, ok := libraryParseEnvironment("BAD KEY=value"); ok {
		t.Fatal("accepted invalid env name")
	}
}

func TestExpandedHandleCancellationAndStreamAdapters(t *testing.T) {
	input, output, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	defer output.Close()
	h := &libraryFileHandle{file: input}
	defer h.close()
	// Stat borrows the native descriptor for birth metadata. Using File.Fd
	// here would switch a pollable pipe into blocking mode and break the read
	// cancellation below.
	librarySuccess(t, h.Operation("stat").Body(RootExecution(), nil))
	lifetime, cancel := context.WithTimeout(context.Background(), 20*time.Millisecond)
	defer cancel()
	ctx := RootExecution()
	ctx.Context = lifetime
	done := make(chan any, 1)
	go func() { defer func() { done <- recover() }(); h.Operation("read").Body(ctx, []Value{int64(1)}) }()
	select {
	case value := <-done:
		if _, ok := value.(cancelled); !ok {
			t.Fatalf("expected cancellation, got %T %v", value, value)
		}
	case <-time.After(time.Second):
		t.Fatal("read was not interrupted")
	}
	ctx = RootExecution()
	dir := t.TempDir()
	fs := &libraryFileSystem{dir}
	view := librarySuccess(t, fs.Operation("open").Body(ctx, []Value{"streams", "w+", int64(0600)}))
	h = view.(View).Receiver.(*libraryFileHandle)
	writer := h.Operation("writer").Body(ctx, nil)
	librarySuccess(t, Bind(writer, "", "write").(Function).Body(ctx, []Value{Bytes{[]byte("line\n")}}))
	librarySuccess(t, Bind(writer, "", "flush").(Function).Body(ctx, nil))
	librarySuccess(t, h.Operation("seek").Body(ctx, []Value{int64(0), int64(0)}))
	reader := h.Operation("reader").Body(ctx, nil)
	librarySuccess(t, Bind(reader, "", "read").(Function).Body(ctx, []Value{int64(10)}))
	Bind(reader, "", "close").(Function).Body(ctx, nil)
	libraryFailure(t, Bind(writer, "", "write").(Function).Body(ctx, []Value{Bytes{[]byte("closed")}}), "Closed")
}
func TestExpandedWatcherCancellation(t *testing.T) {
	ctx := RootExecution()
	fs := &libraryFileSystem{t.TempDir()}
	resource := librarySuccess(t, fs.Operation("watch").Body(ctx, []Value{".", false, Duration(time.Hour), int64(10)}))
	defer Invoke(ctx, Bind(resource, "", "close"), nil)
	lifetime, cancel := context.WithTimeout(ctx.Context, 20*time.Millisecond)
	defer cancel()
	limited := *ctx
	limited.Context = lifetime
	done := make(chan any, 1)
	go func() { defer func() { done <- recover() }(); Invoke(&limited, Bind(resource, "", "next"), nil) }()
	select {
	case value := <-done:
		if _, ok := value.(cancelled); !ok {
			t.Fatalf("expected cancellation, got %T %v", value, value)
		}
	case <-time.After(time.Second):
		t.Fatal("wait was not cancelled")
	}
}
func TestExpandedMetadataAndCopySymlinks(t *testing.T) {
	if goruntime.GOOS == "windows" {
		t.Skip("Unix metadata and link test")
	}
	ctx := RootExecution()
	directory := t.TempDir()
	fs := &libraryFileSystem{directory}
	call := func(n string, a ...Value) Value { return fs.Operation(n).Body(ctx, a) }
	librarySuccess(t, call("write_file", "file", Bytes{[]byte("original")}, false))
	librarySuccess(t, call("hard_link", "file", "hard"))
	librarySuccess(t, call("create_link", "sym", "file"))
	librarySuccess(t, call("chown", "file", int64(os.Getuid()), int64(os.Getgid()), true))
	stamp := libraryTimestamp{time.Unix(123456, 123000000).UTC()}
	librarySuccess(t, call("set_times", "file", stamp, stamp, true))
	if librarySuccess(t, call("stat", "file", true)).(Record).Fields["modified"].(libraryTimestamp).t != stamp.t {
		t.Fatal("mtime not set")
	}
	h := librarySuccess(t, call("open", "file", "r+", int64(0600)))
	librarySuccess(t, Bind(h, "", "set_times").(Function).Body(ctx, []Value{stamp, stamp}))
	Bind(h, "", "close").(Function).Body(ctx, nil)
	librarySuccess(t, call("create_directory", "tree", false))
	librarySuccess(t, call("write_file", "tree/a", Bytes{[]byte("copied")}, false))
	librarySuccess(t, call("create_link", "tree/link", "../file"))
	librarySuccess(t, call("create_directory", "dest", false))
	librarySuccess(t, call("create_link", "dest/a", "../file"))
	librarySuccess(t, call("copy_tree", "tree", "dest", true, int64(3), int64(6)))
	if librarySuccess(t, call("read_file", "file", int64(100))).(Bytes).Items[0] != 'o' {
		t.Fatal("copy followed destination link")
	}
	target := librarySuccess(t, call("read_link", "dest/link"))
	if target != "../file" {
		t.Fatal(target)
	}
}

func TestExpandedProcessDirectoryAndEnvironment(t *testing.T) {
	ctx := RootExecution()
	control := libraryProcessControl{}
	directory := t.TempDir()
	previous, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	defer os.Chdir(previous)
	librarySuccess(t, control.Operation("change_directory").Body(ctx, []Value{directory}))
	if librarySuccess(t, control.Operation("working_directory").Body(ctx, nil)) != directory {
		t.Fatal("cwd did not change")
	}
	fs := &libraryFileSystem{}
	librarySuccess(t, fs.Operation("write_file").Body(ctx, []Value{"relative", Bytes{[]byte("live cwd")}, false}))
	if _, err := os.Stat(filepath.Join(directory, "relative")); err != nil {
		t.Fatal("filesystem retained previous cwd", err)
	}
	key := "MANUSCRIPT_STDLIB_LOAD_ENV"
	t.Setenv(key, "existing")
	envPath := filepath.Join(directory, "environment")
	if err := os.WriteFile(envPath, []byte(key+"=replacement\n"), 0600); err != nil {
		t.Fatal(err)
	}
	librarySuccess(t, control.Operation("load_environment").Body(ctx, []Value{envPath, int64(100)}))
	if os.Getenv(key) != "existing" {
		t.Fatal("loader overwrote existing environment")
	}
	libraryFailure(t, control.Operation("load_environment").Body(ctx, []Value{envPath, int64(0)}), "LimitExceeded")
	if err := os.WriteFile(envPath, []byte(key+"=replacement\nBAD KEY=no\n"), 0600); err != nil {
		t.Fatal(err)
	}
	libraryFailure(t, control.Operation("load_environment").Body(ctx, []Value{envPath, int64(100)}), "InvalidData")
	if os.Getenv(key) != "existing" {
		t.Fatal("invalid environment file changed state")
	}
	libraryFailure(t, control.Operation("send_signal").Body(ctx, []Value{int64(-2147483649), int64(0)}), "InvalidInput")
	libraryFailure(t, control.Operation("set_identity").Body(ctx, []Value{"unknown", int64(1)}), "InvalidInput")
	libraryFailure(t, control.Operation("set_groups").Body(ctx, []Value{libraryList("Int", []Value{int64(-1)})}), "InvalidInput")
	libraryFailure(t, control.Operation("replace").Body(ctx, []Value{"\x00", libraryStrings([]string{"arg"}), &Map{Type: "@std/Map[String][String]"}}), "InvalidInput")
}

func TestNativeFileWatchRetainsTransientEventsAndJoins(t *testing.T) {
	if goruntime.GOOS == "darwin" {
		t.Skip("kqueue may coalesce a transient child into a parent event; retention is exercised by the persistent event test")
	}
	ctx := RootExecution()
	directory := t.TempDir()
	fs := &libraryFileSystem{directory}
	view := librarySuccess(t, fs.Operation("watch_native").Body(ctx, []Value{".", true, int64(20), int64(128), "error"}))
	defer Bind(view, "", "close").(Function).Body(Shield(ctx), nil)
	// Both operations finish before the consumer starts; a polling snapshot would
	// see no file and lose the creation/deletion entirely.
	transient := filepath.Join(directory, "transient")
	if err := os.WriteFile(transient, []byte("short lived"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.Remove(transient); err != nil {
		t.Fatal(err)
	}
	lifetime, cancel := context.WithTimeout(ctx.Context, time.Second)
	defer cancel()
	limited := *ctx
	limited.Context = lifetime
	found := false
	for i := 0; i < 8 && !found; i++ {
		events := librarySuccess(t, Bind(view, "", "next").(Function).Body(&limited, nil)).(*List)
		for _, value := range events.Items {
			if value.(Record).Fields["path"] == transient {
				found = true
			}
		}
	}
	if !found {
		t.Fatal("transient event was lost")
	}
	Bind(view, "", "close").(Function).Body(ctx, nil)
	libraryFailure(t, Bind(view, "", "next").(Function).Body(ctx, nil), "Closed")
	native := view.(View).Receiver.(*libraryNativeWatcher)
	select {
	case <-native.workerDone:
	default:
		t.Fatal("watch worker not joined")
	}
}
func TestNativeFileWatchOverflowAndCancellation(t *testing.T) {
	for _, mode := range []string{"error", "ignore"} {
		t.Run(mode, func(t *testing.T) {
			ctx := RootExecution()
			fs := &libraryFileSystem{t.TempDir()}
			view := librarySuccess(t, fs.Operation("watch_native").Body(ctx, []Value{".", false, int64(5), int64(1), mode}))
			w := view.(View).Receiver.(*libraryNativeWatcher)
			defer Bind(view, "", "close").(Function).Body(Shield(ctx), nil)
			for _, name := range []string{"one", "two", "three", "four", "five", "six"} {
				if err := os.WriteFile(filepath.Join(fs.directory, name), []byte("many kernel events"), 0600); err != nil {
					t.Fatal(err)
				}
			}
			// The pump must finish on overflow in error mode; ignore mode stays alive.
			if mode == "error" {
				select {
				case <-w.workerDone:
					libraryFailure(t, Bind(view, "", "next").(Function).Body(ctx, nil), "LimitExceeded")
				case <-time.After(time.Second):
					t.Fatal("overflow did not terminate watch pump")
				}
			} else {
				librarySuccess(t, Bind(view, "", "next").(Function).Body(ctx, nil))
			}
		})
	}
	ctx := RootExecution()
	fs := &libraryFileSystem{t.TempDir()}
	view := librarySuccess(t, fs.Operation("watch_native").Body(ctx, []Value{".", false, int64(5), int64(10), "error"}))
	defer Bind(view, "", "close").(Function).Body(Shield(ctx), nil)
	lifetime, cancel := context.WithTimeout(ctx.Context, 20*time.Millisecond)
	defer cancel()
	ctx.Context = lifetime
	done := make(chan any, 1)
	go func() { defer func() { done <- recover() }(); Bind(view, "", "next").(Function).Body(ctx, nil) }()
	select {
	case value := <-done:
		if _, ok := value.(cancelled); !ok {
			t.Fatal(value)
		}
	case <-time.After(time.Second):
		t.Fatal("native watcher wait did not cancel")
	}
}

func TestFilesystemCopyOptions(t *testing.T) {
	ctx := RootExecution()
	directory := t.TempDir()
	fs := &libraryFileSystem{directory}
	options := Record{"@std/CopyOptions", map[string]Value{"recursive": true, "replace": true, "error_on_exists": false, "dereference": false, "preserve_timestamps": true, "verbatim_symlinks": true, "clone": "try", "max_entries": int64(50), "max_bytes": int64(10000)}}
	copy := func(src, dst string, filter Value) Value {
		return fs.Operation("copy").Body(ctx, []Value{src, dst, options, filter})
	}
	noFilter := optional("fn(source:String;destination:String)->Bool", nil, false)
	if err := os.MkdirAll(filepath.Join(directory, "source/sub"), 0700); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{"keep", "skip"} {
		if err := os.WriteFile(filepath.Join(directory, "source/sub", name), []byte(name), 0600); err != nil {
			t.Fatal(err)
		}
	}
	stamp := time.Unix(10000, 123000000)
	if err := os.Chtimes(filepath.Join(directory, "source/sub/keep"), stamp, stamp); err != nil {
		t.Fatal(err)
	}
	filter := NewFunction([]string{"source", "destination"}, "Bool", func(_ *Execution, a []Value) Value { return filepath.Base(a[0].(string)) != "skip" })
	librarySuccess(t, copy("source", "copy", optional("fn(source:String;destination:String)->Bool", filter, true)))
	if _, err := os.Stat(filepath.Join(directory, "copy/sub/skip")); !os.IsNotExist(err) {
		t.Fatal("filter ignored", err)
	}
	info, err := os.Stat(filepath.Join(directory, "copy/sub/keep"))
	if err != nil || !info.ModTime().Equal(stamp) {
		t.Fatal("timestamps not preserved", info, err)
	}
	options.Fields["replace"] = false
	options.Fields["error_on_exists"] = true
	libraryFailure(t, copy("source", "copy", noFilter), "AlreadyExists")
	options.Fields["error_on_exists"] = false
	librarySuccess(t, copy("source", "copy", noFilter))
	options.Fields["recursive"] = false
	libraryFailure(t, copy("source", "not-recursive", noFilter), "InvalidInput")
	options.Fields["recursive"] = true
	options.Fields["max_bytes"] = int64(0)
	libraryFailure(t, copy("source", "bounded", noFilter), "LimitExceeded")
	if goruntime.GOOS != "windows" {
		options.Fields["max_bytes"] = int64(10000)
		if err := os.Symlink("missing", filepath.Join(directory, "broken")); err != nil {
			t.Fatal(err)
		}
		librarySuccess(t, copy("broken", "broken-copy", noFilter))
		target, err := os.Readlink(filepath.Join(directory, "broken-copy"))
		if err != nil || target != "missing" {
			t.Fatal("broken link not copied verbatim", target, err)
		}
		options.Fields["verbatim_symlinks"] = false
		librarySuccess(t, copy("broken", "absolute-copy", noFilter))
		target, err = os.Readlink(filepath.Join(directory, "absolute-copy"))
		if err != nil || !filepath.IsAbs(target) {
			t.Fatal("relative link not resolved", target, err)
		}
		if err := os.Symlink("source/sub/keep", filepath.Join(directory, "link")); err != nil {
			t.Fatal(err)
		}
		options.Fields["dereference"] = true
		librarySuccess(t, copy("link", "followed", noFilter))
		data, err := os.ReadFile(filepath.Join(directory, "followed"))
		if err != nil || string(data) != "keep" {
			t.Fatal("link not dereferenced", string(data), err)
		}
		if err := os.Symlink("..", filepath.Join(directory, "source/sub/cycle")); err != nil {
			t.Fatal(err)
		}
		libraryFailure(t, copy("source", "cycle-copy", noFilter), "InvalidInput")
	}
}

func TestFilesystemGlobOptions(t *testing.T) {
	ctx := RootExecution()
	directory := t.TempDir()
	fs := &libraryFileSystem{directory}
	for _, name := range []string{"a/one.txt", "a/two.js", "skip/hidden.txt", "c/three.txt"} {
		path := filepath.Join(directory, filepath.FromSlash(name))
		if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte("data"), 0600); err != nil {
			t.Fatal(err)
		}
	}
	options := Record{"@std/GlobOptions", map[string]Value{"patterns": libraryStrings([]string{"**/*.txt", "a/*.js"}), "exclude": libraryStrings([]string{"skip/**"}), "follow_links": false, "max_entries": int64(30), "max_results": int64(10)}}
	noExclude := optional("fn(entry:PathEntry)->Bool", nil, false)
	read := func(exclude Value) Value {
		return fs.Operation("glob_entries").Body(ctx, []Value{".", options, exclude})
	}
	entries := librarySuccess(t, read(noExclude)).(*List)
	if len(entries.Items) != 3 {
		t.Fatal(entries)
	}
	exclude := NewFunction([]string{"entry"}, "Bool", func(_ *Execution, a []Value) Value {
		return a[0].(Record).Fields["path"] == filepath.Join("c", "three.txt")
	})
	entries = librarySuccess(t, read(optional("fn(entry:PathEntry)->Bool", exclude, true))).(*List)
	if len(entries.Items) != 2 {
		t.Fatal(entries)
	}
	options.Fields["max_results"] = int64(1)
	libraryFailure(t, read(noExclude), "LimitExceeded")
	options.Fields["max_results"] = int64(10)
	options.Fields["max_entries"] = int64(1)
	libraryFailure(t, read(noExclude), "LimitExceeded")
	if goruntime.GOOS != "windows" {
		options.Fields["max_entries"] = int64(50)
		options.Fields["follow_links"] = true
		if err := os.Symlink("a", filepath.Join(directory, "alias")); err != nil {
			t.Fatal(err)
		}
		entries = librarySuccess(t, read(noExclude)).(*List)
		if len(entries.Items) != 4 {
			t.Fatal("directory symlink not traversed", entries)
		}
	}
}

func TestNodeConstantCatalogs(t *testing.T) {
	if goruntime.GOOS != "linux" {
		t.Skip("recorded native values are from Linux; other targets use their OS constants")
	}
	data, err := os.ReadFile("testdata/node-constants.json")
	if err != nil {
		t.Fatal(err)
	}
	var catalogs map[string]map[string]any
	if err = json.Unmarshal(data, &catalogs); err != nil {
		t.Fatal(err)
	}
	for _, module := range []string{"os", "fs"} {
		name := "system/constants"
		if module == "fs" {
			name = "fs/constants"
		}
		spec := libraryFunctions[name]
		actual := StandardFunction(name, libraryRuntimeType(spec.Result)).(Function).Body(RootExecution(), nil).(*Map)
		values := map[string]int64{}
		for _, e := range actual.Entries {
			values[e.Key.(string)] = e.Value.(int64)
		}
		check := func(name string, n float64) {
			value, exists := values[name]
			if !exists || value != int64(n) {
				t.Errorf("%s constant %s: got %d (exists %v), Node expected %d", module, name, value, exists, int64(n))
			}
		}
		for name, value := range catalogs[module] {
			if nested, ok := value.(map[string]any); ok {
				for name, value := range nested {
					check(name, value.(float64))
				}
			} else {
				check(name, value.(float64))
			}
		}
	}
}
func TestFileStatMetadataAndNativeFlags(t *testing.T) {
	ctx := RootExecution()
	fs := &libraryFileSystem{t.TempDir()}
	flags := int64(os.O_CREATE | os.O_RDWR | os.O_EXCL)
	handle := librarySuccess(t, fs.Operation("open_flags").Body(ctx, []Value{"metadata", flags, int64(0640)}))
	defer Bind(handle, "", "close").(Function).Body(ctx, nil)
	librarySuccess(t, fs.Operation("chmod").Body(ctx, []Value{"metadata", int64(0640)}))
	info := librarySuccess(t, Bind(handle, "", "stat").(Function).Body(ctx, nil)).(Record)
	if info.Fields["mode"].(int64)&0170000 != 0100000 || info.Fields["permissions"].(int64) != func() int64 {
		native, err := os.Stat(filepath.Join(fs.directory, "metadata"))
		if err != nil {
			t.Fatal(err)
		}
		return int64(native.Mode().Perm())
	}() {
		t.Fatal(info)
	}
	exact := info.Fields["exact"].(*Map)
	found := false
	for _, entry := range exact.Entries {
		if entry.Key == "mode" {
			found = true
			if entry.Value.(libraryBigInt).n.Int64() != info.Fields["mode"] {
				t.Fatal("exact mode differs")
			}
		}
	}
	if !found {
		t.Fatal("missing exact metadata")
	}
	if goruntime.GOOS == "linux" {
		if info.Fields["blocks"].(int64) < 0 || info.Fields["block_size"].(int64) <= 0 {
			t.Fatal("missing allocation metadata")
		}
	}
	libraryFailure(t, fs.Operation("open_flags").Body(ctx, []Value{"invalid", int64(-1), int64(0600)}), "InvalidInput")
}

func TestNativeFileWatchPersistentEvent(t *testing.T) {
	ctx := RootExecution()
	directory := t.TempDir()
	fs := &libraryFileSystem{directory}
	view := librarySuccess(t, fs.Operation("watch_native").Body(ctx, []Value{".", false, int64(20), int64(64), "error"}))
	defer Bind(view, "", "close").(Function).Body(Shield(ctx), nil)
	path := filepath.Join(directory, "created")
	if err := os.WriteFile(path, []byte("retained"), 0600); err != nil {
		t.Fatal(err)
	}
	lifetime, cancel := context.WithTimeout(ctx.Context, 2*time.Second)
	defer cancel()
	limited := *ctx
	limited.Context = lifetime
	events := librarySuccess(t, Bind(view, "", "next").(Function).Body(&limited, nil)).(*List)
	if len(events.Items) == 0 {
		t.Fatal("native event missing")
	}
}

func TestProcessSignalStreamAndMonotonicTime(t *testing.T) {
	ctx := RootExecution()
	control := libraryProcessControl{}
	first := control.Operation("monotonic_time").Body(ctx, nil).(int64)
	second := control.Operation("monotonic_time").Body(ctx, nil).(int64)
	if second < first {
		t.Fatal("monotonic process clock moved backwards")
	}
	if goruntime.GOOS == "windows" {
		return
	}
	n := hostos.Constants()["SIGUSR1"]
	view := librarySuccess(t, control.Operation("watch_signals").Body(ctx, []Value{libraryList("Int", []Value{n}), int64(4)}))
	defer Bind(view, "", "close").(Function).Body(Shield(ctx), nil)
	librarySuccess(t, control.Operation("send_signal").Body(ctx, []Value{int64(os.Getpid()), n}))
	lifetime, cancel := context.WithTimeout(ctx.Context, time.Second)
	defer cancel()
	limited := *ctx
	limited.Context = lifetime
	if librarySuccess(t, Bind(view, "", "next").(Function).Body(&limited, nil)) != n {
		t.Fatal("wrong signal")
	}
	Bind(view, "", "close").(Function).Body(ctx, nil)
	libraryFailure(t, Bind(view, "", "next").(Function).Body(ctx, nil), "Closed")
}

func TestFileSystemErrorMapping(t *testing.T) {
	ctx := RootExecution()
	dir := t.TempDir()
	fs := &libraryFileSystem{dir}
	call := func(name string, a ...Value) Value { return fs.Operation(name).Body(ctx, a) }
	librarySuccess(t, call("create_directory", "dir", false))
	librarySuccess(t, call("write_file", "dir/child", Bytes{[]byte("x")}, false))
	librarySuccess(t, call("write_file", "file", Bytes{[]byte("abc")}, false))
	libraryFailure(t, call("remove", "dir", false), "NotEmpty")
	libraryFailure(t, call("list", "file", nil), "InvalidInput")
	libraryFailure(t, call("read_file", "dir", nil), "InvalidInput")
	libraryFailure(t, call("create_directory", "file", false), "AlreadyExists")

	ro := librarySuccess(t, call("open", "file", "r", int64(0)))
	write := func(h Value, name string, a ...Value) Value {
		fn := Bind(h, "", name).(Function)
		var args []Argument
		for i, v := range a {
			args = append(args, Argument{Name: fn.Labels[i], Value: v})
		}
		return Invoke(ctx, fn, args)
	}
	defer write(ro, "close")
	libraryFailure(t, write(ro, "write_file", Bytes{[]byte("z")}), "InvalidInput")
	libraryFailure(t, write(ro, "seek", int64(-1), int64(0)), "InvalidInput")
}
