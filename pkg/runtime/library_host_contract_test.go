//go:build !ms_lean

package msruntime

import (
	"errors"
	"io"
	"net"
	"os"
	"path/filepath"
	goruntime "runtime"
	"syscall"
	"testing"
	"time"
)

func TestExpandedSystemAndProcessMonotonicNanoseconds(t *testing.T) {
	ctx := RootExecution()
	control := libraryProcessControl{}
	// Bracket against time.Duration's nanosecond representation and origin,
	// rather than inferring units from the public method name or a loose delay.
	for range 3 {
		before := int64(time.Since(libraryProcessStarted))
		reading := control.Operation("monotonic_time").Body(ctx, nil).(int64)
		after := int64(time.Since(libraryProcessStarted))
		if reading < before || reading > after {
			t.Fatalf("monotonic_time = %d; want elapsed nanoseconds in [%d, %d]", reading, before, after)
		}
		beforeUptime := Duration(time.Since(libraryProcessStarted))
		uptime := librarySuccess(t, control.Operation("uptime").Body(ctx, nil)).(Duration)
		afterUptime := Duration(time.Since(libraryProcessStarted))
		if uptime < beforeUptime || uptime > afterUptime {
			t.Fatalf("process uptime = %d; want same origin in [%d, %d]", uptime, beforeUptime, afterUptime)
		}
	}
}

func TestExpandedSystemAndProcessTempQueryVersusCreation(t *testing.T) {
	ctx := RootExecution()
	root := filepath.Join(t.TempDir(), "absent-root")
	if goruntime.GOOS == "windows" {
		// Windows chooses TMP before TEMP through GetTempPath.
		t.Setenv("TMP", root)
		t.Setenv("TEMP", root)
	} else {
		t.Setenv("TMPDIR", root)
	}
	system := &librarySystem{}
	queried := librarySuccess(t, system.Operation("temporary_directory").Body(ctx, nil)).(string)
	if filepath.Clean(queried) != filepath.Clean(root) {
		t.Fatalf("temp root query = %q, want %q", queried, root)
	}
	if _, err := os.Stat(root); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("temp root query created/validated the root: %v", err)
	}
	if err := os.Mkdir(root, 0700); err != nil {
		t.Fatal(err)
	}
	fs := &libraryFileSystem{t.TempDir()}
	path := librarySuccess(t, fs.Operation("temporary_directory").Body(ctx, []Value{"created-"})).(string)
	if filepath.Dir(path) != filepath.Clean(root) {
		t.Fatalf("temp factory base = %s", path)
	}
	if _, err := os.Stat(path); err != nil {
		t.Fatal(err)
	}
	if err := os.Remove(path); err != nil {
		t.Fatal(err)
	}
	scoped := librarySuccess(t, fs.Operation("temporary").Body(ctx, []Value{"scoped-"}))
	scopedPath := NativeAccessorRead(ctx, scoped, "path").(string)
	Bind(scoped, "", "close").(Function).Body(Shield(ctx), nil)
	if _, err := os.Stat(scopedPath); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("scoped temp remains: %v", err)
	}
}

func TestFileSystemHostContractValidation(t *testing.T) {
	ctx := RootExecution()
	fs := &libraryFileSystem{t.TempDir()}
	for _, flags := range []int64{-1, 2147483648} {
		libraryFailure(t, fs.Operation("open_flags").Body(ctx, []Value{"path", flags, int64(0600)}), "InvalidInput")
	}
	for _, mode := range []int64{-1, 4096} {
		libraryFailure(t, fs.Operation("open").Body(ctx, []Value{"path", "w", mode}), "InvalidInput")
		libraryFailure(t, fs.Operation("chmod").Body(ctx, []Value{"path", mode}), "InvalidInput")
	}
	for _, mode := range []int64{-1, 8} {
		libraryFailure(t, fs.Operation("access").Body(ctx, []Value{"path", mode}), "InvalidInput")
	}
	for _, policy := range []string{"ERROR", "Ignore", ""} {
		libraryFailure(t, fs.Operation("watch_native").Body(ctx, []Value{".", false, int64(10), int64(10), policy}), "InvalidInput")
	}
	handle := librarySuccess(t, fs.Operation("open").Body(ctx, []Value{"file", "w+", int64(0600)}))
	defer Bind(handle, "", "close").(Function).Body(Shield(ctx), nil)
	for _, origin := range []int64{-1, 3} {
		libraryFailure(t, Bind(handle, "", "seek").(Function).Body(ctx, []Value{int64(0), origin}), "InvalidInput")
	}
	reader := Bind(handle, "", "reader").(Function).Body(ctx, nil)
	libraryFailure(t, Bind(reader, "", "read").(Function).Body(ctx, []Value{int64(0)}), "InvalidInput")
	options := Record{"@std/CopyOptions", map[string]Value{
		"recursive": false, "replace": false, "error_on_exists": false,
		"dereference": false, "preserve_timestamps": false, "verbatim_symlinks": false,
		"clone": "NONE", "max_entries": int64(10), "max_bytes": int64(10),
	}}
	for _, policy := range []string{"NONE", "Try", ""} {
		options.Fields["clone"] = policy
		libraryFailure(t, fs.Operation("copy").Body(ctx, []Value{"file", "copy", options, optional("fn(source:String;destination:String)->Bool", nil, false)}), "InvalidInput")
	}
	control := libraryProcessControl{}
	for _, kind := range []string{"UID", "effective_uid", ""} {
		libraryFailure(t, control.Operation("set_identity").Body(ctx, []Value{kind, int64(0)}), "InvalidInput")
	}
}

// A peer can receive a prefix before the write fails. The Result retains the
// domain error, not a successful byte count or a rollback guarantee.
func TestNativeConnectionWritePrefixOnFailure(t *testing.T) {
	ctx := RootExecution()
	socket, peer := net.Pipe()
	connection := newLibraryConnection(socket)
	defer connection.close()
	defer peer.Close()
	finished := make(chan Value, 1)
	go func() {
		finished <- connection.Operation("write").Body(ctx, []Value{Bytes{[]byte("abcdef")}, nativeNoTimeout})
	}()
	if err := peer.SetReadDeadline(time.Now().Add(time.Second)); err != nil {
		t.Fatal(err)
	}
	prefix := make([]byte, 2)
	if _, err := io.ReadFull(peer, prefix); err != nil {
		t.Fatal(err)
	}
	if string(prefix) != "ab" {
		t.Fatalf("external prefix = %q", prefix)
	}
	peer.Close()
	select {
	case result := <-finished:
		libraryFailure(t, result, "Failed")
		cause := result.(Alternative).Fields[0].(Alternative)
		if cause.Type != "@std/IoError" || len(cause.Fields) != 1 || cause.Fields[0] == "" {
			t.Fatalf("lost write failure identity/payload: %#v", cause)
		}
	case <-time.After(time.Second):
		t.Fatal("write did not finish after peer close")
	}
}

func TestProcessSignalStreamCapacityContract(t *testing.T) {
	ctx := RootExecution()
	control := libraryProcessControl{}
	signals := libraryList("Int", []Value{int64(syscall.SIGINT)})
	for _, test := range []struct {
		name     string
		capacity Value
		want     int
	}{
		{"none", optional("Int", nil, false), 128},
		{"explicit", optional("Int", int64(4), true), 4},
	} {
		t.Run(test.name, func(t *testing.T) {
			view := librarySuccess(t, control.Operation("watch_signals").Body(ctx, []Value{signals, test.capacity})).(View)
			observer := view.Receiver.(*librarySignalStream)
			defer observer.Operation("close").Body(Shield(ctx), nil)
			if got := cap(observer.events); got != test.want {
				t.Fatalf("signal buffer capacity = %d; want %d", got, test.want)
			}
		})
	}
	for _, capacity := range []int64{-1, 0, 1048577} {
		libraryFailure(t, control.Operation("watch_signals").Body(ctx, []Value{signals, optional("Int", capacity, true)}), "InvalidInput")
	}
}
