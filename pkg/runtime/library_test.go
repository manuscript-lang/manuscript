package msruntime

import (
	"archive/zip"
	"bytes"
	"context"
	"crypto/ed25519"
	"encoding/hex"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func libraryCall(t *testing.T, name string, a ...Value) Alternative {
	t.Helper()
	spec, ok := libraryFunctions[name]
	if !ok {
		t.Fatal(name)
	}
	return StandardFunction(name, libraryRuntimeType(spec.Result)).(Function).Body(RootExecution(), a).(Alternative)
}
func librarySuccess(t *testing.T, v Value) Value {
	t.Helper()
	a := v.(Alternative)
	if a.Tag != "ok" {
		t.Fatalf("expected success: %#v", a)
	}
	return a.Fields[0]
}
func libraryFailure(t *testing.T, v Value, code string) {
	t.Helper()
	a := v.(Alternative)
	if a.Tag != "error" || a.Fields[0].(Alternative).Tag != code {
		t.Fatalf("expected %s: %#v", code, a)
	}
	cause := a.Fields[0].(Alternative)
	if !strings.HasSuffix(a.Type, "]["+cause.Type+"]") {
		t.Fatalf("error identity does not match Result: %#v", a)
	}
}
func TestLibraryCodecsAndNumbers(t *testing.T) {
	for _, s := range []string{"Zh==", "Zg=", "Zg==\n", "_w=="} {
		libraryFailure(t, libraryCall(t, "encoding/base64_decode", s, false, int64(100)), "InvalidData")
	}
	libraryFailure(t, libraryCall(t, "encoding/hex_decode", "0001", int64(1)), "LimitExceeded")
	if got := librarySuccess(t, libraryCall(t, "encoding/base64_decode", "Zg==", false, int64(1))).(Bytes); string(got.Items) != "f" {
		t.Fatal(got)
	}
	for _, s := range []string{" 1", "1_0", "0x10", "+", "١"} {
		libraryFailure(t, libraryCall(t, "numbers/parse_int", s, int64(10)), "InvalidData")
	}
	for _, s := range []string{"0x1p2", " 1.0", "1_0", "1."} {
		libraryFailure(t, libraryCall(t, "numbers/parse_float", s), "InvalidData")
	}
	libraryFailure(t, libraryCall(t, "binary/read_integer", Bytes{[]byte{255, 255, 255, 255, 255, 255, 255, 255}}, int64(0), int64(8), false, false), "OutOfRange")
	for _, little := range []bool{false, true} {
		for _, n := range []int64{-9223372036854775808, -32768, -1, 0, 32767, 9223372036854775807} {
			data := librarySuccess(t, libraryCall(t, "binary/write_integer", n, int64(8), true, little))
			got := librarySuccess(t, libraryCall(t, "binary/read_integer", data, int64(0), int64(8), true, little))
			if got != n {
				t.Fatal(n, got)
			}
		}
	}
}
func TestLibraryJSONBoundaries(t *testing.T) {
	limits := Record{"@std/JsonLimits", map[string]Value{"max_bytes": int64(1000), "max_depth": int64(8), "max_values": int64(32)}}
	for _, s := range []string{`{"a":1,"\u0061":2}`, `"\uD800"`, `"\uDC00"`, `1 2`, `NaN`, `[1,]`} {
		libraryFailure(t, libraryCall(t, "json/parse", s, limits), "InvalidData")
	}
	value := librarySuccess(t, libraryCall(t, "json/parse", `{"n":9007199254740993,"x":"\uD83D\uDE00"}`, limits))
	text := librarySuccess(t, libraryCall(t, "json/stringify", value, int64(1000))).(string)
	if !strings.Contains(text, "9007199254740993") || !strings.Contains(text, "😀") {
		t.Fatal(text)
	}
	libraryFailure(t, libraryCall(t, "json/stringify", value, int64(5)), "LimitExceeded")
	bad := Alternative{"@std/JsonValue", "NumberValue", []Value{"1 true"}}
	libraryFailure(t, libraryCall(t, "json/stringify", bad, int64(100)), "InvalidData")
}
func TestLibraryCryptoVectors(t *testing.T) {
	key := Bytes{[]byte(strings.Repeat("k", 32))}
	nonce := Bytes{make([]byte, 12)}
	plain := Bytes{[]byte("private")}
	aad := Bytes{[]byte("header")}
	encrypted := librarySuccess(t, libraryCall(t, "crypto/seal", key, nonce, plain, aad))
	if got := librarySuccess(t, libraryCall(t, "crypto/open", key, nonce, encrypted, aad)); !Equal(got, plain) {
		t.Fatal(got)
	}
	changed := Bytes{append([]byte{}, encrypted.(Bytes).Items...)}
	changed.Items[0] ^= 1
	libraryFailure(t, libraryCall(t, "crypto/open", key, nonce, changed, aad), "AuthenticationFailed")
	derived := librarySuccess(t, libraryCall(t, "crypto/derive_key", Bytes{[]byte("password")}, Bytes{[]byte("salt")}, int64(1), int64(32))).(Bytes)
	if hex.EncodeToString(derived.Items) != "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b" {
		t.Fatal(hex.EncodeToString(derived.Items))
	}
	seed := Bytes{make([]byte, ed25519.SeedSize)}
	public := librarySuccess(t, libraryCall(t, "crypto/public_key", seed))
	signature := librarySuccess(t, libraryCall(t, "crypto/sign", seed, plain))
	f := StandardFunction("crypto/verify", "Bool").(Function)
	if !f.Body(RootExecution(), []Value{public, plain, signature}).(bool) {
		t.Fatal("verification")
	}
}
func TestLibraryCompressionAndArchives(t *testing.T) {
	for _, format := range []string{"gzip", "zlib", "deflate"} {
		input := Bytes{[]byte(strings.Repeat("abcd", 1000))}
		compressed := librarySuccess(t, libraryCall(t, "compress/compress", input, format, int64(6), int64(10000)))
		if got := librarySuccess(t, libraryCall(t, "compress/decompress", compressed, format, int64(4000))); !Equal(got, input) {
			t.Fatal(format)
		}
		libraryFailure(t, libraryCall(t, "compress/decompress", compressed, format, int64(3999)), "LimitExceeded")
		data := Bytes{append(append([]byte{}, compressed.(Bytes).Items...), 1)}
		libraryFailure(t, libraryCall(t, "compress/decompress", data, format, int64(4000)), "InvalidData")
	}
	limits := Record{"@std/ArchiveLimits", map[string]Value{"max_entries": int64(2), "max_entry_bytes": int64(4), "max_total_bytes": int64(4)}}
	entry := func(path string, data string, directory bool) Value {
		return Record{"@std/ArchiveEntry", map[string]Value{"path": path, "data": Bytes{[]byte(data)}, "directory": directory}}
	}
	for _, format := range []string{"zip", "tar"} {
		entries := libraryList("@std/ArchiveEntry", []Value{entry("dir", "", true), entry("dir/x", "data", false)})
		packed := librarySuccess(t, libraryCall(t, "archive/pack", entries, format, int64(10000)))
		got := librarySuccess(t, libraryCall(t, "archive/unpack", packed, format, limits))
		if !Equal(got, entries) {
			t.Fatalf("%s: %#v", format, got)
		}
	}
	for _, format := range []string{"zip", "tar"} {
		// A trailing slash on a directory is accepted by pack but unpack returns the canonical slashless path.
		packed := librarySuccess(t, libraryCall(t, "archive/pack", libraryList("@std/ArchiveEntry", []Value{entry("d/", "", true)}), format, int64(10000)))
		got := librarySuccess(t, libraryCall(t, "archive/unpack", packed, format, limits))
		if want := libraryList("@std/ArchiveEntry", []Value{entry("d", "", true)}); !Equal(got, want) {
			t.Fatalf("%s trailing slash: %#v", format, got)
		}
	}
	for _, path := range []string{"../x", "/x", "C:/x", "a\\b", "a/../x"} {
		entries := libraryList("@std/ArchiveEntry", []Value{entry(path, "x", false)})
		libraryFailure(t, libraryCall(t, "archive/pack", entries, "zip", int64(1000)), "InvalidInput")
	}
}
func TestLibraryZipPackRejectsOverlongName(t *testing.T) {
	entry := func(path string, directory bool) Value {
		return Record{"@std/ArchiveEntry", map[string]Value{"path": path, "data": Bytes{}, "directory": directory}}
	}
	long := strings.Repeat("a", 65536)
	// A 65535-byte name is the largest ZIP can store; a directory's trailing slash counts toward the limit.
	librarySuccess(t, libraryCall(t, "archive/pack", libraryList("@std/ArchiveEntry", []Value{entry(long[:65535], false)}), "zip", int64(1<<30)))
	libraryFailure(t, libraryCall(t, "archive/pack", libraryList("@std/ArchiveEntry", []Value{entry(long, false)}), "zip", int64(1<<30)), "InvalidInput")
	libraryFailure(t, libraryCall(t, "archive/pack", libraryList("@std/ArchiveEntry", []Value{entry(long[:65535], true)}), "zip", int64(1<<30)), "InvalidInput")
	librarySuccess(t, libraryCall(t, "archive/pack", libraryList("@std/ArchiveEntry", []Value{entry(long, false)}), "tar", int64(1<<30)))
}
func TestLibraryZipNamesWithoutUTF8Flag(t *testing.T) {
	// Info-ZIP and other writers store UTF-8 names without general-purpose flag 0x800.
	// Go's reader marks names containing `~`, control bytes, or non-ASCII as NonUTF8
	// in that case, but valid UTF-8 text must still unpack.
	big := Record{"@std/ArchiveLimits", map[string]Value{"max_entries": int64(10), "max_entry_bytes": int64(100), "max_total_bytes": int64(100)}}
	build := func(name string) Bytes {
		var buffer bytes.Buffer
		writer := zip.NewWriter(&buffer)
		out, err := writer.CreateHeader(&zip.FileHeader{Name: name, Method: zip.Store, NonUTF8: true})
		if err != nil {
			t.Fatal(err)
		}
		out.Write([]byte("x"))
		if err := writer.Close(); err != nil {
			t.Fatal(err)
		}
		return Bytes{buffer.Bytes()}
	}
	for _, name := range []string{"backup~", "a~b/c", "caf\u00e9.txt"} {
		got := librarySuccess(t, libraryCall(t, "archive/unpack", build(name), "zip", big))
		items := got.(*List).Items
		if len(items) != 1 || items[0].(Record).Fields["path"] != name {
			t.Fatalf("%q: %#v", name, got)
		}
	}
	libraryFailure(t, libraryCall(t, "archive/unpack", build("bad\xff"), "zip", big), "Unsupported")
}
func TestLibraryFilesystem(t *testing.T) {
	ctx := RootExecution()
	directory := t.TempDir()
	fs := &libraryFileSystem{directory}
	call := func(name string, a ...Value) Value { return fs.Operation(name).Body(ctx, a) }
	librarySuccess(t, call("write_file", "x", Bytes{[]byte("abc")}, false))
	libraryFailure(t, call("write_file", "x", Bytes{[]byte("overwrite")}, false), "AlreadyExists")
	libraryFailure(t, call("read_file", "x", int64(2)), "LimitExceeded")
	if got := librarySuccess(t, call("read_file", "x", int64(3))).(Bytes); string(got.Items) != "abc" {
		t.Fatal(got)
	}
	librarySuccess(t, call("create_directory", "tree", false))
	outside := filepath.Join(t.TempDir(), "keep")
	if err := os.WriteFile(outside, []byte("keep"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(outside, filepath.Join(directory, "tree", "link")); err != nil {
		t.Fatal(err)
	}
	librarySuccess(t, call("remove", "tree", true))
	if _, err := os.Stat(outside); err != nil {
		t.Fatal("followed symlink", err)
	}
}
func TestLibraryHTTPClient(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/redirect" {
			http.Redirect(w, r, "/body", 302)
			return
		}
		w.Header().Add("X-Duplicate", "a")
		w.Header().Add("X-Duplicate", "b")
		w.WriteHeader(404)
		io.WriteString(w, "body")
	}))
	defer server.Close()
	n := &network{}
	ctx := RootExecution()
	headers := &libraryHeaders{}
	call := func(path string, max int64) Value {
		return n.Operation("request").Body(ctx, []Value{libraryHTTPMethod("GET"), server.URL + path, headers, Bytes{}, max, Duration(time.Second)})
	}
	response := librarySuccess(t, call("/body", 4)).(Record)
	if response.Fields["head"].(Record).Fields["status"] != int64(404) || string(response.Fields["body"].(Bytes).Items) != "body" {
		t.Fatal(response)
	}
	libraryFailure(t, call("/body", 3), "LimitExceeded")
	libraryFailure(t, n.Operation("request").Body(ctx, []Value{libraryHTTPMethod("GET"), "http://127.0.0.1:99999/", headers, Bytes{}, int64(10), Duration(time.Second)}), "InvalidInput")
	redirect := librarySuccess(t, call("/redirect", 1000)).(Record)
	if redirect.Fields["head"].(Record).Fields["status"] != int64(302) {
		t.Fatal("followed redirect")
	}
	n.Operation("close").Body(ctx, nil)
	libraryFailure(t, call("/body", 4), "Closed")
}
func TestLibraryConnectionCloseAndCancellation(t *testing.T) {
	left, right := net.Pipe()
	c := newLibraryConnection(left)
	defer right.Close()
	ctx := RootExecution()
	done := make(chan Value, 1)
	go func() { done <- c.Operation("read").Body(ctx, []Value{int64(10)}) }()
	c.close()
	select {
	case v := <-done:
		libraryFailureIO(t, v, "Closed")
	case <-time.After(time.Second):
		t.Fatal("read did not wake")
	}
	libraryFailureIO(t, c.Operation("write").Body(ctx, []Value{Bytes{[]byte("x")}}), "Closed")
	left2, right2 := net.Pipe()
	defer right2.Close()
	c2 := newLibraryConnection(left2)
	defer c2.close()
	cancelledCtx, cancel := context.WithCancel(context.Background())
	exec := newExecution(ctx, cancelledCtx)
	stopped := make(chan any, 1)
	go func() { defer func() { stopped <- recover() }(); c2.Operation("read").Body(exec, []Value{int64(1)}) }()
	cancel()
	select {
	case value := <-stopped:
		if _, ok := value.(cancelled); !ok {
			t.Fatalf("expected cancellation: %v", value)
		}
	case <-time.After(time.Second):
		t.Fatal("cancel blocked")
	}
}
func libraryFailureIO(t *testing.T, v Value, code string) {
	t.Helper()
	a := v.(Alternative)
	if a.Tag != "error" || a.Fields[0].(Alternative).Tag != code {
		t.Fatalf("expected IO %s: %#v", code, a)
	}
}

func TestLibraryDatagramBoundaries(t *testing.T) {
	ctx := RootExecution()
	n := &network{}
	defer n.Operation("close").Body(ctx, nil)
	left := librarySuccess(t, n.Operation("bind_datagram").Body(ctx, []Value{"127.0.0.1:0"}))
	right := librarySuccess(t, n.Operation("bind_datagram").Body(ctx, []Value{"127.0.0.1:0"}))
	address := Invoke(ctx, Bind(right, "", "address"), nil).(string)
	for _, data := range [][]byte{{}, []byte("ok")} {
		librarySuccess(t, Invoke(ctx, Bind(left, "", "send"), []Argument{{"data", Bytes{data}}, {"address", address}}))
		packet := librarySuccess(t, Invoke(ctx, Bind(right, "", "receive"), []Argument{{"max_bytes", int64(2)}})).(Record)
		if string(packet.Fields["data"].(Bytes).Items) != string(data) {
			t.Fatal(packet)
		}
	}
	librarySuccess(t, Invoke(ctx, Bind(left, "", "send"), []Argument{{"data", Bytes{[]byte("long")}}, {"address", address}}))
	libraryFailure(t, Invoke(ctx, Bind(right, "", "receive"), []Argument{{"max_bytes", int64(2)}}), "LimitExceeded")
}
func TestLibraryNetworkCloseInterruptsRequest(t *testing.T) {
	started := make(chan struct{})
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { close(started); <-r.Context().Done() }))
	defer server.Close()
	ctx := RootExecution()
	n := &network{}
	done := make(chan Value, 1)
	go func() {
		done <- n.Operation("request").Body(ctx, []Value{libraryHTTPMethod("GET"), server.URL, &libraryHeaders{}, Bytes{}, int64(100), Duration(10 * time.Second)})
	}()
	<-started
	n.Operation("close").Body(ctx, nil)
	select {
	case value := <-done:
		libraryFailure(t, value, "Closed")
	case <-time.After(time.Second):
		t.Fatal("request escaped network close")
	}
}
func TestLibraryTCPRoundTrip(t *testing.T) {
	ctx := RootExecution()
	n := &network{}
	defer n.Operation("close").Body(ctx, nil)
	listener := librarySuccess(t, n.Operation("listen").Body(ctx, []Value{"127.0.0.1:0"}))
	address := Invoke(ctx, Bind(listener, "", "address"), nil).(string)
	client := librarySuccess(t, n.Operation("connect").Body(ctx, []Value{address, Duration(time.Second)}))
	server := librarySuccess(t, Invoke(ctx, Bind(listener, "", "accept"), nil))
	librarySuccess(t, Invoke(ctx, Bind(client, "", "write"), []Argument{{"data", Bytes{[]byte("ping")}}}))
	part := librarySuccess(t, Invoke(ctx, Bind(server, "", "read"), []Argument{{"max_bytes", int64(4)}})).(Alternative)
	if part.Tag != "some" || string(part.Fields[0].(Bytes).Items) != "ping" {
		t.Fatal(part)
	}
	librarySuccess(t, Invoke(ctx, Bind(client, "", "shutdown_write"), nil))
	eof := librarySuccess(t, Invoke(ctx, Bind(server, "", "read"), []Argument{{"max_bytes", int64(1)}})).(Alternative)
	if eof.Tag != "none" {
		t.Fatal(eof)
	}
	librarySuccess(t, Invoke(ctx, Bind(server, "", "write"), []Argument{{"data", Bytes{[]byte("pong")}}}))
	part = librarySuccess(t, Invoke(ctx, Bind(client, "", "read"), []Argument{{"max_bytes", int64(4)}})).(Alternative)
	if string(part.Fields[0].(Bytes).Items) != "pong" {
		t.Fatal(part)
	}
}

func TestLibraryErrorsKeepDomainIdentity(t *testing.T) {
	limits := Record{"@std/JsonLimits", map[string]Value{"max_bytes": int64(100), "max_depth": int64(8), "max_values": int64(32)}}
	for _, tt := range []struct {
		name, errorType, code string
		args                  []Value
	}{
		{"json/parse", "JsonError", "InvalidData", []Value{"[", limits}},
		{"encoding/hex_decode", "EncodingError", "InvalidData", []Value{"zz", int64(10)}},
		{"numbers/parse_int", "NumberError", "OutOfRange", []Value{"9223372036854775808", int64(10)}},
		{"binary/write_integer", "BinaryError", "OutOfRange", []Value{int64(256), int64(1), false, false}},
		{"string/from_scalars", "StringError", "InvalidInput", []Value{libraryList("Int", []Value{int64(-1)})}},
		{"url/parse_query", "UrlError", "LimitExceeded", []Value{"a=1", int64(0)}},
		{"regex/compile", "RegexError", "InvalidData", []Value{"["}},
		{"time/parse_timestamp", "TimeError", "InvalidData", []Value{"yesterday"}},
		{"tls/parse_certificates", "TlsError", "InvalidData", []Value{"invalid PEM", int64(10)}},
		{"net/parse_ip", "NetworkError", "InvalidData", []Value{"invalid address"}},
	} {
		t.Run(tt.name, func(t *testing.T) {
			result := libraryCall(t, tt.name, tt.args...)
			libraryFailure(t, result, tt.code)
			if cause := result.Fields[0].(Alternative); cause.Type != "@std/"+tt.errorType {
				t.Fatalf("wrong error identity: %#v", cause)
			}
		})
	}
	fs := &libraryFileSystem{directory: t.TempDir()}
	result := fs.Operation("read_file").Body(RootExecution(), []Value{"missing", int64(100)}).(Alternative)
	libraryFailure(t, result, "NotFound")
	if cause := result.Fields[0].(Alternative); cause.Type != "@std/FileSystemError" {
		t.Fatalf("wrong filesystem error identity: %#v", cause)
	}
}

type failingLibraryStream struct{ cause Alternative }

func (s failingLibraryStream) Operation(name string) Function {
	result := "@std/Result[Unit][@std/IoError]"
	labels := []string{"data"}
	if name == "read" {
		result = "@std/Result[@std/Optional[@std/Bytes]][@std/IoError]"
		labels = []string{"max_bytes"}
	}
	return NewFunction(labels, result, func(*Execution, []Value) Value {
		return Alternative{result, "error", []Value{s.cause}}
	})
}

func TestLibraryStreamErrorsPreserveCauses(t *testing.T) {
	for _, cause := range []Alternative{
		{"@std/IoError", "Closed", nil},
		{"@std/IoError", "Unavailable", nil},
		{"@std/IoError", "Failed", []Value{"device diagnostic"}},
	} {
		t.Run(cause.Tag, func(t *testing.T) {
			stream := failingLibraryStream{cause}
			for _, name := range []string{"io/read_all", "io/read_line", "io/copy"} {
				args := []Value{stream, int64(100)}
				if name == "io/copy" {
					args = []Value{stream, stream, int64(100)}
				}
				result := libraryCall(t, name, args...)
				libraryFailure(t, result, cause.Tag)
				if !Equal(result.Fields[0], cause) {
					t.Fatalf("%s lost cause: %#v", name, result)
				}
			}
			copied := libraryCall(t, "io/copy", &networkingReadStream{data: []byte("data")}, stream, int64(100))
			libraryFailure(t, copied, cause.Tag)
			if !Equal(copied.Fields[0], cause) {
				t.Fatalf("copy lost output cause: %#v", copied)
			}
			transport := newLogTransport(stream, nil)
			logger := librarySuccess(t, libraryCall(t, "log/create", transport, Alternative{Type: "@std/LogLevel", Tag: "Info"}, &Map{}, false, int64(1000)))
			result := Invoke(RootExecution(), Bind(logger, "", "info"), []Argument{{"message", "message"}, {"fields", &Map{}}}).(Alternative)
			libraryFailure(t, result, "Io")
			wrapped := result.Fields[0].(Alternative)
			if wrapped.Type != "@std/LogError" || len(wrapped.Fields) != 1 || !Equal(wrapped.Fields[0], cause) {
				t.Fatalf("logging lost cause: %#v", result)
			}
		})
	}
}
