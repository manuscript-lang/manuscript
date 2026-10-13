//go:build !ms_lean

package msruntime

import (
	"bufio"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"reflect"
	"sort"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func TestHTTPBufferedResponseHeaderCollisions(t *testing.T) {
	for _, reverse := range []bool{false, true} {
		t.Run(map[bool]string{false: "forward", true: "reverse"}[reverse], func(t *testing.T) {
			entries := []Entry{
				{"x-dup", "first"}, {"X-Dup", "second"},
				{"Set-Cookie", "a=1; Expires=Wed, 21 Oct 2037 07:28:00 GMT"}, {"set-cookie", "b=2"},
				{"X-Empty", ""}, {"X-Text", "é\t🙂"},
			}
			wantDup := []string{"first", "second"}
			wantCookies := []string{entries[2].Value.(string), "b=2"}
			if reverse {
				entries[0], entries[1] = entries[1], entries[0]
				entries[2], entries[3] = entries[3], entries[2]
				wantDup[0], wantDup[1] = wantDup[1], wantDup[0]
				wantCookies[0], wantCookies[1] = wantCookies[1], wantCookies[0]
			}
			handler := NewFunction([]string{"request"}, "@std/HttpResponse", func(_ *Execution, _ []Value) Value {
				response := hostResponse(200, "ok").(Record)
				response.Fields["headers"] = &Map{Type: "@std/Map[String][String]", Entries: entries}
				return response
			})
			service := serveTest(t, RootExecution(), handler, 1024)
			client := &http.Client{Timeout: 2 * time.Second}
			response, err := client.Get("http://" + service.listener.Addr().String())
			if err != nil {
				t.Fatal(err)
			}
			defer response.Body.Close()
			if response.StatusCode != 200 || !reflect.DeepEqual(response.Header.Values("x-dup"), wantDup) || !reflect.DeepEqual(response.Header.Values("SET-cookie"), wantCookies) {
				t.Fatalf("status %d, headers %#v; want duplicates %q, cookies %q", response.StatusCode, response.Header, wantDup, wantCookies)
			}
			if !reflect.DeepEqual(response.Header.Values("X-Empty"), []string{""}) || response.Header.Get("X-Text") != "é\t🙂" {
				t.Fatalf("empty/UTF-8 headers lost: %#v", response.Header)
			}
			body, err := io.ReadAll(response.Body)
			if err != nil || string(body) != "ok" {
				t.Fatalf("body %q, error %v", body, err)
			}
		})
	}
}

func TestHTTPClientHeaderCollisions(t *testing.T) {
	ctx := RootExecution()
	n := &network{}
	defer n.Operation("close").Body(ctx, nil)
	client := librarySuccess(t, n.Operation("http_client").Body(ctx, []Value{networkingClientOptions()}))
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header()["X-Dup"] = r.Header.Values("x-dup")
		w.Header().Add("Set-Cookie", "a=1; Expires=Wed, 21 Oct 2037 07:28:00 GMT")
		w.Header().Add("set-cookie", "b=2")
		w.Header().Set("X-Empty", "")
		io.Copy(w, r.Body)
	}))
	defer server.Close()
	for _, method := range []string{"request", "send", "send_stream"} {
		for _, reverse := range []bool{false, true} {
			t.Run(method+map[bool]string{false: "/forward", true: "/reverse"}[reverse], func(t *testing.T) {
				entries := []Entry{{"x-dup", "first"}, {"X-Dup", "second"}}
				want := []string{"first", "second"}
				if reverse {
					entries[0], entries[1] = entries[1], entries[0]
					want[0], want[1] = want[1], want[0]
				}
				args := []Value{"POST", server.URL, &Map{Type: "@std/Map[String][String]", Entries: entries}, Bytes{[]byte("ok")}, int64(10), Duration(2 * time.Second)}
				var headers *Map
				if method == "request" {
					response := librarySuccess(t, n.Operation(method).Body(ctx, args)).(Record)
					headers = response.Fields["headers"].(*Map)
					if string(response.Fields["body"].(Bytes).Items) != "ok" {
						t.Fatal(response)
					}
				} else {
					if method == "send_stream" {
						args[3] = ViewOf("@std/ReadStream", &networkingReadStream{data: []byte("ok")})
					}
					body := librarySuccess(t, networkingInvoke(ctx, client, method, args...))
					defer networkingInvoke(ctx, body, "close")
					headers = networkingInvoke(ctx, body, "headers").(*Map)
					part := librarySuccess(t, networkingInvoke(ctx, body, "read", int64(10))).(Alternative)
					if part.Tag != "some" || string(part.Fields[0].(Bytes).Items) != "ok" {
						t.Fatal(part)
					}
				}
				assertHTTPHeaderMap(t, headers, map[string][]string{
					"X-Dup": want, "X-Empty": {""},
					"Set-Cookie": {"a=1; Expires=Wed, 21 Oct 2037 07:28:00 GMT", "b=2"},
				})
			})
		}
	}
}

func assertHTTPHeaderMap(t *testing.T, headers *Map, want map[string][]string) {
	t.Helper()
	keys := []string{}
	for _, entry := range headers.Entries {
		key := entry.Key.(string)
		keys = append(keys, key)
		if values, ok := want[key]; ok {
			if got := libraryStringValues(entry.Value); !reflect.DeepEqual(got, values) {
				t.Errorf("%s: got %q, want %q", key, got, values)
			}
			delete(want, key)
		}
	}
	if !sort.StringsAreSorted(keys) || len(want) != 0 {
		t.Fatalf("keys %q, missing %v", keys, want)
	}
}

func TestHTTPStreamingHeaderCollisions(t *testing.T) {
	ctx := RootExecution()
	n := &network{}
	defer n.Operation("close").Body(ctx, nil)
	handler := NewFunction([]string{"exchange"}, "@std/Result[Unit][@std/HttpError]", func(child *Execution, args []Value) Value {
		headers := networkingInvoke(child, args[0], "headers").(*Map)
		// Copying the list map keeps separate received values, including empties.
		forward := &Map{Type: headers.Type}
		for _, entry := range headers.Entries {
			if !httpHeaderNameEqual(entry.Key.(string), "Connection") {
				forward.Entries = append(forward.Entries, entry)
			}
		}
		headers = forward
		headers.Entries = append(headers.Entries, Entry{"set-cookie", libraryStrings([]string{"c=3", "d=4"})})
		return networkingInvoke(child, args[0], "send_headers", int64(200), headers)
	})
	server := librarySuccess(t, n.Operation("serve_stream").Body(ctx, []Value{"127.0.0.1:0", handler, networkingServerOptions()}))
	address := networkingInvoke(ctx, server, "address").(string)
	// Raw loopback request exercises the parser's case folding and repeated fields.
	response := rawHTTPHeaderRequest(t, address, "x-dup: first\r\nX-Dup: second\r\nX-Dup: third\r\nX-Empty: \r\nSet-Cookie: a=1\r\nset-cookie: b=2\r\n")
	defer response.Body.Close()
	if response.StatusCode != 200 || !reflect.DeepEqual(response.Header.Values("X-Dup"), []string{"first", "second", "third"}) || !reflect.DeepEqual(response.Header.Values("Set-Cookie"), []string{"a=1", "b=2", "c=3", "d=4"}) || !reflect.DeepEqual(response.Header.Values("X-Empty"), []string{""}) {
		t.Fatalf("streamed headers: %d %#v", response.StatusCode, response.Header)
	}
}

func rawHTTPHeaderRequest(t *testing.T, address, headers string) *http.Response {
	t.Helper()
	conn, err := net.DialTimeout("tcp", address, 2*time.Second)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { conn.Close() })
	conn.SetDeadline(time.Now().Add(2 * time.Second))
	if _, err := io.WriteString(conn, "GET / HTTP/1.1\r\nHost: "+address+"\r\nConnection: close\r\n"+headers+"\r\n"); err != nil {
		t.Fatal(err)
	}
	response, err := http.ReadResponse(bufio.NewReader(conn), nil)
	if err != nil {
		t.Fatal(err)
	}
	return response
}

func TestHTTPMalformedOutgoingHeaders(t *testing.T) {
	for _, tc := range []struct{ name, key, value string }{
		{"empty name", "", "ok"}, {"space in name", "X Bad", "ok"}, {"colon in name", "X:Bad", "ok"},
		{"unicode name", "X-é", "ok"}, {"nonascii fold", "K", "ok"},
		{"CR", "X-Bad", "bad\rvalue"}, {"LF", "X-Bad", "bad\nvalue"}, {"NUL", "X-Bad", "bad\x00value"},
		{"control", "X-Bad", "bad\x01value"}, {"DEL", "X-Bad", "bad\x7fvalue"},
		{"invalid UTF-8", "X-Bad", "\xff"},
		{"content length", "cOnTeNt-LeNgTh", "1"}, {"transfer encoding", "TRANSFER-encoding", "chunked"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			ctx := RootExecution()
			n := &network{}
			defer n.Operation("close").Body(ctx, nil)
			entries := []Entry{{"X-Prefix", "validated first"}, {tc.key, tc.value}}
			out := &Map{Type: "@std/Map[String][String]", Entries: entries}
			buffered := serveTest(t, ctx, NewFunction([]string{"request"}, "@std/HttpResponse", func(_ *Execution, _ []Value) Value {
				response := hostResponse(200, "ok").(Record)
				response.Fields["headers"] = out
				return response
			}), 1024)
			response, err := (&http.Client{Timeout: 2 * time.Second}).Get("http://" + buffered.listener.Addr().String())
			if err != nil {
				t.Fatal(err)
			}
			response.Body.Close()
			if response.StatusCode != 500 || response.Header.Get("X-Prefix") != "" {
				t.Fatalf("partial invalid buffered headers: %d %#v", response.StatusCode, response.Header)
			}
			var requests atomic.Int64
			peer := httptest.NewServer(http.HandlerFunc(func(http.ResponseWriter, *http.Request) { requests.Add(1) }))
			defer peer.Close()
			args := []Value{"GET", peer.URL, out, Bytes{}, int64(10), Duration(2 * time.Second)}
			libraryFailure(t, n.Operation("request").Body(ctx, args), "InvalidInput")
			client := librarySuccess(t, n.Operation("http_client").Body(ctx, []Value{networkingClientOptions()}))
			libraryFailure(t, networkingInvoke(ctx, client, "send", args...), "InvalidInput")
			args[3] = ViewOf("@std/ReadStream", &networkingReadStream{})
			libraryFailure(t, networkingInvoke(ctx, client, "send_stream", args...), "InvalidInput")
			if requests.Load() != 0 {
				t.Fatal("invalid client headers reached peer")
			}
			// Failed send_headers is recoverable and emits none of the valid prefix.
			result := make(chan Value, 1)
			handler := NewFunction([]string{"exchange"}, "@std/Result[Unit][@std/HttpError]", func(child *Execution, a []Value) Value {
				multi := &Map{Type: "@std/Map[String][@std/List[String]]", Entries: []Entry{{"X-Prefix", libraryStrings([]string{"valid"})}, {tc.key, libraryStrings([]string{tc.value})}}}
				result <- networkingInvoke(child, a[0], "send_headers", int64(200), multi)
				return networkingInvoke(child, a[0], "send_headers", int64(201), &Map{Type: multi.Type})
			})
			server := librarySuccess(t, n.Operation("serve_stream").Body(ctx, []Value{"127.0.0.1:0", handler, networkingServerOptions()}))
			address := networkingInvoke(ctx, server, "address").(string)
			response, err = (&http.Client{Timeout: 2 * time.Second}).Get("http://" + address)
			if err != nil {
				t.Fatal(err)
			}
			response.Body.Close()
			libraryFailure(t, <-result, "InvalidInput")
			if response.StatusCode != 201 || response.Header.Get("X-Prefix") != "" {
				t.Fatalf("partial invalid streaming headers: %d %#v", response.StatusCode, response.Header)
			}
		})
	}
}

func TestHTTPHeaderUTF8Boundaries(t *testing.T) {
	ctx := RootExecution()
	n := &network{}
	defer n.Operation("close").Body(ctx, nil)
	peer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { w.Header().Set("X-Raw", "\xff") }))
	defer peer.Close()
	args := []Value{"GET", peer.URL, &Map{Type: "@std/Map[String][String]"}, Bytes{}, int64(10), Duration(2 * time.Second)}
	libraryFailure(t, n.Operation("request").Body(ctx, args), "InvalidData")
	client := librarySuccess(t, n.Operation("http_client").Body(ctx, []Value{networkingClientOptions()}))
	libraryFailure(t, networkingInvoke(ctx, client, "send", args...), "InvalidData")
	buffered := serveTest(t, ctx, NewFunction([]string{"request"}, "@std/HttpResponse", func(child *Execution, args []Value) Value {
		value := Invoke(child, NativeMember(args[0], "header"), []Argument{{"name", "x-RAW"}}).(Alternative)
		if value.Tag != "some" || !reflect.DeepEqual(value.Fields[0].(Bytes).Items, []byte{255}) {
			return hostResponse(500, "bytes lost")
		}
		text := Invoke(child, NativeMember(value.Fields[0], "to_text"), nil).(Alternative)
		if text.Tag != "none" {
			return hostResponse(500, "invalid UTF-8 decoded")
		}
		return hostResponse(200, "ok")
	}), 1024)
	response := rawHTTPHeaderRequest(t, buffered.listener.Addr().String(), "X-Raw: \xff\r\n")
	response.Body.Close()
	if response.StatusCode != 200 {
		t.Fatal("buffered request did not preserve raw bytes", response.StatusCode)
	}
	var invoked atomic.Bool
	handler := NewFunction([]string{"exchange"}, "@std/Result[Unit][@std/HttpError]", func(_ *Execution, _ []Value) Value {
		invoked.Store(true)
		return libraryOK("@std/Result[Unit][@std/HttpError]", Unit{})
	})
	server := librarySuccess(t, n.Operation("serve_stream").Body(ctx, []Value{"127.0.0.1:0", handler, networkingServerOptions()}))
	response = rawHTTPHeaderRequest(t, networkingInvoke(ctx, server, "address").(string), "X-Raw: \xff\r\n")
	response.Body.Close()
	if response.StatusCode != 400 || invoked.Load() {
		t.Fatal("streaming request admitted invalid UTF-8", response.StatusCode)
	}
}

func TestHTTPMalformedIncomingHeaders(t *testing.T) {
	ctx := RootExecution()
	n := &network{}
	defer n.Operation("close").Body(ctx, nil)
	var invoked atomic.Bool
	buffered := serveTest(t, ctx, NewFunction([]string{"request"}, "@std/HttpResponse", func(_ *Execution, _ []Value) Value {
		invoked.Store(true)
		return hostResponse(200, "unexpected")
	}), 1024)
	handler := NewFunction([]string{"exchange"}, "@std/Result[Unit][@std/HttpError]", func(_ *Execution, _ []Value) Value {
		invoked.Store(true)
		return libraryOK("@std/Result[Unit][@std/HttpError]", Unit{})
	})
	streaming := librarySuccess(t, n.Operation("serve_stream").Body(ctx, []Value{"127.0.0.1:0", handler, networkingServerOptions()}))
	for _, address := range []string{buffered.listener.Addr().String(), networkingInvoke(ctx, streaming, "address").(string)} {
		for _, header := range []string{"Bad Name: x\r\n", "X-é: x\r\n", "X-Bad: \x00\r\n", "X-Bad: \x01\r\n", "X-Bad: \x7f\r\n", "X-Bad: embedded\rvalue\r\n"} {
			response := rawHTTPHeaderRequest(t, address, header)
			response.Body.Close()
			if response.StatusCode != 400 || invoked.Load() {
				t.Fatalf("malformed input %q: status %d, handler called %v", header, response.StatusCode, invoked.Load())
			}
		}
	}
}

func TestHTTPHeaderBridgePreservesExactEntries(t *testing.T) {
	// Direct host maps need not have the parser's canonical keys. Canonicalizing
	// lookup with Header.Values would repeat one spelling's values and lose others.
	headers := http.Header{"x-dup": {"first", ""}, "X-Dup": {"second"}}
	assertHTTPHeaderMap(t, libraryHTTPHeaders(headers), map[string][]string{"x-dup": {"first", ""}, "X-Dup": {"second"}})
	if strings.Join(headers["x-dup"], ",") != "first," {
		t.Fatal("bridge mutated host map")
	}
}
