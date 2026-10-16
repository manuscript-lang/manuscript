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

func textOf(h *List[*Bytes]) []string {
	out := []string{}
	for _, v := range h.Items {
		out = append(out, string(v.Data))
	}
	return out
}

func TestHeadersAliasingAndText(t *testing.T) {
	ctx := testExec()
	h := headersOf("x-test", "first", "Other", "skip", "X-Test", "second", "K", "ascii")
	first := HttpHeaders_Values(ctx, h, "X-TEST")
	second := HttpHeaders_Values(ctx, h, "x-test")
	if !first.Some || first.Val != second.Val || !reflect.DeepEqual(textOf(first.Val), []string{"first", "second"}) {
		t.Fatal("lookup lost values or copied membership")
	}
	// ASCII folding only: the Kelvin sign is not a K.
	if HttpHeaders_Values(ctx, h, "\u212a").Some {
		t.Fatal("Unicode folding")
	}
	if HttpHeaders_Values(ctx, h, "absent").Some {
		t.Fatal("absent header")
	}
	first.Val.Items[0] = NewBytes([]byte("mutated"))
	must(t, HttpHeaders_Append(ctx, h, "X-TEST", NewBytes(nil)))
	if !reflect.DeepEqual(textOf(second.Val), []string{"mutated", "second", ""}) {
		t.Fatal("append did not share membership")
	}
	clone := HttpHeaders_Clone(ctx, h)
	cloned := HttpHeaders_Values(ctx, clone, "x-test").Val
	cloned.Items[0] = NewBytes([]byte("clone"))
	if string(first.Val.Items[0].Data) != "mutated" {
		t.Fatal("clone shares membership")
	}
	first.Val.Items = nil
	got := HttpHeaders_Values(ctx, h, "x-test")
	if !got.Some || len(got.Val.Items) != 0 {
		t.Fatal("present empty list")
	}
	must(t, HttpHeaders_Append(ctx, h, "Raw", NewBytes([]byte{255})))
	failedWith(t, HttpHeaders_Text(ctx, h, "raw"), "HttpError_InvalidData")
	for _, name := range []string{"", "bad name", "bad:name", "é", "x\r\ny"} {
		failedWith(t, HttpHeaders_Append(ctx, h, name, NewBytes(nil)), "HttpError_InvalidInput")
	}
	if names := HttpHeaders_Names(ctx, h).Items; !reflect.DeepEqual(names, []string{"x-test", "Other", "K", "Raw"}) {
		t.Fatal(names)
	}
	text := must(t, HttpHeaders_Text(ctx, headersOf("A", "1", "a", "2"), "a"))
	if !text.Some || !reflect.DeepEqual(text.Val.Items, []string{"1", "2"}) {
		t.Fatal(text)
	}
	if must(t, HttpHeaders_Text(ctx, h, "nothing")).Some {
		t.Fatal("absent text")
	}
	if !HttpHeaders_Remove(ctx, h, "OTHER") || HttpHeaders_Remove(ctx, h, "other") {
		t.Fatal("remove")
	}
	if names := HttpHeaders_Names(ctx, h).Items; !reflect.DeepEqual(names, []string{"x-test", "K", "Raw"}) {
		t.Fatal(names)
	}
	// Re-adding after removal appends a fresh entry in order.
	must(t, HttpHeaders_Append(ctx, h, "other", NewBytes([]byte("again"))))
	if names := HttpHeaders_Names(ctx, h).Items; !reflect.DeepEqual(names, []string{"x-test", "K", "Raw", "other"}) {
		t.Fatal(names)
	}
}

func TestMetadataAliasesShareHeaders(t *testing.T) {
	ctx := testExec()
	headers := headersOf("X-Test", "first")
	response := &ClientResponse{Head: &HttpResponseMetadata{Status: 200, Headers: headers}, Body: NewBytes(nil)}
	first := ClientResponse_Metadata(ctx, response)
	first.Status = 999
	must(t, HttpHeaders_Append(ctx, first.Headers, "x-test", NewBytes([]byte("second"))))
	next := ClientResponse_Metadata(ctx, response)
	if next.Status != 999 || next.Headers != headers || !reflect.DeepEqual(headerValues(headers, "X-Test"), []string{"first", "second"}) {
		t.Fatal("metadata alias contract")
	}
}

func TestHttpMethodText(t *testing.T) {
	ctx := testExec()
	for method, want := range map[HttpMethod]string{HttpMethod_Get{}: "GET", HttpMethod_Head{}: "HEAD", HttpMethod_Post{}: "POST", HttpMethod_Put{}: "PUT", HttpMethod_Patch{}: "PATCH", HttpMethod_Delete{}: "DELETE", HttpMethod_Connect{}: "CONNECT", HttpMethod_Options{}: "OPTIONS", HttpMethod_Trace{}: "TRACE", HttpMethod_Custom{Value: "PURGE"}: "PURGE"} {
		if got := HttpMethod_Text(ctx, method); got != want {
			t.Fatal(got, want)
		}
		if got := HttpMethod_Text(ctx, methodOf(want)); got != want {
			t.Fatal(got, want)
		}
	}
	if _, ok := methodOf("GET").(HttpMethod_Get); !ok {
		t.Fatal("GET should map to the case")
	}
}

func TestHttpErrorMessages(t *testing.T) {
	ctx := testExec()
	if got := Errors_Message_HttpError(ctx, HttpError_Failed{Message: "dial tcp 192.0.2.1:80: refused"}); got != "dial tcp 192.0.2.1:80: refused" {
		t.Fatal(got)
	}
	if got := Errors_Message_HttpError(ctx, HttpError_Timeout{}); got != "HTTP: operation timed out" {
		t.Fatal(got)
	}
	if got := Errors_Message_WebSocketError(ctx, WebSocketError_Closed{}); got != "WebSocket: resource is closed" {
		t.Fatal(got)
	}
	if got := Errors_Message_WebSocketError(ctx, WebSocketError_Failed{Message: "x"}); got != "x" {
		t.Fatal(got)
	}
}

func TestNormalizeRequestPath(t *testing.T) {
	for target, want := range map[string]string{
		"/a/b":         "/a/b",
		"/a%20b":       "/a b",
		"/a/../b":      "/b",
		"/%2e%2e/x":    "/x",
		"/a/./b/":      "/a/b/",
		"/../../etc":   "/etc",
		"/x?y=%2F":     "/x",
		"/files/a%2Fb": "",
		"/files/a%2fb": "",
		"/a%00b":       "",
	} {
		r := httptest.NewRequest("GET", target, nil)
		ok := normalizeRequestPath(r)
		if want == "" {
			if ok {
				t.Errorf("%s accepted as %q", target, r.URL.Path)
			}
		} else if !ok || r.URL.Path != want {
			t.Errorf("%s: got %q %v, want %q", target, r.URL.Path, ok, want)
		}
	}
}

// pathHandlerHeaders echoes the routed path and query in response headers.
func pathHeaders(path, query string) *HttpHeaders {
	return headersOf("X-Path", path, "X-Query", query, "x-dup", "first", "X-Dup", "second", "Set-Cookie", "a=1", "set-cookie", "b=2")
}

func TestHttpPathContractLoopback(t *testing.T) {
	for _, streaming := range []bool{false, true} {
		t.Run(map[bool]string{false: "buffered", true: "streaming"}[streaming], func(t *testing.T) {
			ctx, n := newTestNetwork(t)
			var calls atomic.Int64
			var server HttpServer
			if streaming {
				server = must(t, n.ServeStream(ctx, "127.0.0.1:0", func(child *Execution, e HttpExchange) Result[Unit, HttpError] {
					calls.Add(1)
					return e.SendHeaders(child, 200, pathHeaders(e.Path(child), e.Query(child)))
				}, serverOptions()))
			} else {
				server = must(t, n.Serve(ctx, "127.0.0.1:0", func(_ *Execution, r *HttpRequest) *HttpResponse {
					calls.Add(1)
					return &HttpResponse{Status: 200, Headers: pathHeaders(r.Path, r.Query), Body: NewBytes([]byte("ok"))}
				}, None[int](), None[int](), None[int](), None[Duration](), None[Duration]()))
			}
			address := server.Address(ctx)
			client := &http.Client{Timeout: 2 * time.Second}
			for _, tc := range []struct{ target, path, query string }{
				{"/a/b", "/a/b", ""}, {"/a%20b", "/a b", ""},
				{"/a/../b", "/b", ""}, {"/%2e%2e/x", "/x", ""},
				{"/a/./b/", "/a/b/", ""}, {"/../../etc", "/etc", ""},
				{"/a//b", "/a/b", ""}, {"/x?y=%2F", "/x", "y=%2F"},
				{"/a%252Fb?x=%2500", "/a%2Fb", "x=%2500"},
				{"/a%2Fb", "", ""}, {"/a%2fb", "", ""}, {"/a%00b", "", ""},
				{"/bad%ff/../x", "", ""},
			} {
				before := calls.Load()
				response, err := client.Get("http://" + address + tc.target)
				if err != nil {
					t.Fatal(err)
				}
				io.Copy(io.Discard, response.Body)
				response.Body.Close()
				if tc.path == "" {
					if response.StatusCode != 400 || calls.Load() != before {
						t.Errorf("%s: status %d, handler calls %d -> %d", tc.target, response.StatusCode, before, calls.Load())
					}
					continue
				}
				if response.StatusCode != 200 || response.Header.Get("X-Path") != tc.path || response.Header.Get("X-Query") != tc.query {
					t.Errorf("%s: status %d, path %q, query %q", tc.target, response.StatusCode, response.Header.Get("X-Path"), response.Header.Get("X-Query"))
				}
				if !reflect.DeepEqual(response.Header.Values("X-Dup"), []string{"first", "second"}) || !reflect.DeepEqual(response.Header.Values("Set-Cookie"), []string{"a=1", "b=2"}) {
					t.Error("header values lost after path normalization", response.Header)
				}
			}
		})
	}
}

func TestHttpInvalidPortsAllClients(t *testing.T) {
	ctx, n := newTestNetwork(t)
	client := must(t, n.HttpClient(ctx, clientOptions()))
	for _, address := range []string{"http://127.0.0.1:99999/", "http://127.0.0.1:65536/", "http://127.0.0.1:99999999999999999999999/", "http://127.0.0.1:-1/", "http://[::1", "ftp://127.0.0.1/", "http://user@127.0.0.1/", "http:///x"} {
		failedWith(t, n.Request(ctx, get(), address, headersOf(), NewBytes(nil), Some(int(100)), Some(Duration(time.Second))), "HttpError_InvalidInput")
		failedWith(t, client.Request(ctx, get(), address, headersOf(), NewBytes(nil), Some(int(100)), Some(Duration(time.Second))), "HttpError_InvalidInput")
		failedWith(t, client.RequestStream(ctx, get(), address, headersOf(), &sliceStream{}, Some(int(100)), Some(Duration(time.Second))), "HttpError_InvalidInput")
	}
}

func TestHttpClientPoolingCookiesStreaming(t *testing.T) {
	var requests, connections atomic.Int64
	server := httptest.NewUnstartedServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requests.Add(1)
		switch r.URL.Path {
		case "/redirect":
			http.SetCookie(w, &http.Cookie{Name: "session", Value: "yes", Path: "/"})
			http.Redirect(w, r, "/cookie", 302)
		case "/cookie":
			if cookie, err := r.Cookie("session"); err != nil || cookie.Value != "yes" {
				http.Error(w, "missing cookie", 500)
				return
			}
			io.WriteString(w, "streamed")
		default:
			io.Copy(w, r.Body)
		}
	}))
	server.Config.ConnState = func(_ net.Conn, s http.ConnState) {
		if s == http.StateNew {
			connections.Add(1)
		}
	}
	server.Start()
	defer server.Close()
	ctx, n := newTestNetwork(t)
	client := must(t, n.HttpClient(ctx, clientOptions()))
	for range 2 {
		body := must(t, client.Request(ctx, get(), server.URL+"/redirect", headersOf(), NewBytes(nil), Some(int(100)), Some(Duration(time.Second))))
		if got := readAll(t, ctx, body.Read, 3); got != "streamed" {
			t.Fatal(got)
		}
		body.Close(ctx)
	}
	if connections.Load() != 1 || requests.Load() != 4 {
		t.Fatal("connections", connections.Load(), "requests", requests.Load())
	}
	// Zero redirects returns the redirect response itself.
	options := clientOptions()
	options.MaxRedirects = Some(int(0))
	options.Cookies = false
	plain := must(t, n.HttpClient(ctx, options))
	body := must(t, plain.Request(ctx, get(), server.URL+"/redirect", headersOf(), NewBytes(nil), None[int](), None[Duration]()))
	if body.Metadata(ctx).Status != 302 {
		t.Fatal("redirect followed")
	}
	body.Close(ctx)
	// The response budget is enforced while streaming.
	echo := must(t, client.Request(ctx, post(), server.URL+"/echo", headersOf(), NewBytes([]byte("0123456789")), Some(int(4)), Some(Duration(time.Second))))
	var failure Result[Option[*Bytes], IoError]
	for range 4 {
		failure = echo.Read(ctx, Some(int(3)))
		if failure.Failed {
			break
		}
	}
	failedWith(t, failure, "IoError_Failed")
	echo.Close(ctx)
}

func TestHttpClientOptionsValidation(t *testing.T) {
	ctx, n := newTestNetwork(t)
	for _, mutate := range []func(*HttpClientOptions){
		func(o *HttpClientOptions) { o.MaxRedirects = Some(int(-1)) },
		func(o *HttpClientOptions) { o.MaxIdleConnections = Some(int(-1)) },
		func(o *HttpClientOptions) { o.MaxHeaderBytes = Some(int(0)) },
		func(o *HttpClientOptions) { o.IdleTimeout = Some(Duration(-1)) },
		func(o *HttpClientOptions) { o.Tls = &TlsOptions{RootsPem: "junk"} },
		func(o *HttpClientOptions) { o.Tls = &TlsOptions{RequireClientCertificate: true} },
	} {
		o := clientOptions()
		mutate(o)
		failedWith(t, n.HttpClient(ctx, o), "HttpError_InvalidInput")
	}
	must(t, n.HttpClient(ctx, &HttpClientOptions{}))
}

func TestHttpClientCloseIsIdempotentAndJoins(t *testing.T) {
	block := make(chan struct{})
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(200)
		w.(http.Flusher).Flush()
		select {
		case <-block:
		case <-r.Context().Done():
		}
	}))
	defer server.Close()
	defer close(block)
	ctx, n := newTestNetwork(t)
	client := must(t, n.HttpClient(ctx, clientOptions()))
	body := must(t, client.Request(ctx, get(), server.URL, headersOf(), NewBytes(nil), None[int](), None[Duration]()))
	done := make(chan Result[Option[*Bytes], IoError], 1)
	go func() { done <- body.Read(ctx, Some(int(1))) }()
	time.Sleep(30 * time.Millisecond)
	client.Close(ctx)
	client.Close(ctx)
	select {
	case r := <-done:
		if !r.Failed {
			t.Fatal("read should fail once the client closed")
		}
	case <-time.After(2 * time.Second):
		t.Fatal("client close did not interrupt reads")
	}
	failedWith(t, body.Read(ctx, None[int]()), "IoError_Closed")
	if body.Metadata(ctx).Status != 200 {
		t.Fatal("metadata unreadable after close")
	}
	failedWith(t, client.Request(ctx, get(), server.URL, headersOf(), NewBytes(nil), None[int](), None[Duration]()), "HttpError_Closed")
}

func TestNetworkRequestBuffered(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/redirect" {
			http.Redirect(w, r, "/target", 302)
			return
		}
		if r.URL.Path == "/slow" {
			time.Sleep(300 * time.Millisecond)
		}
		w.Header().Set("X-Method", r.Method)
		w.WriteHeader(404)
		io.Copy(w, r.Body)
	}))
	defer server.Close()
	ctx, n := newTestNetwork(t)
	r := must(t, n.Request(ctx, post(), server.URL+"/x", headersOf("X-In", "v"), NewBytes([]byte("payload")), Some(int(100)), Some(Duration(time.Second))))
	if r.Head.Status != 404 || str(r.Body) != "payload" || !reflect.DeepEqual(headerValues(r.Head.Headers, "x-method"), []string{"POST"}) {
		t.Fatalf("%+v", r.Head)
	}
	// Error statuses are ordinary responses and redirects are returned.
	if redirect := must(t, n.Request(ctx, get(), server.URL+"/redirect", headersOf(), NewBytes(nil), None[int](), None[Duration]())); redirect.Head.Status != 302 {
		t.Fatal(redirect.Head.Status)
	}
	failedWith(t, n.Request(ctx, post(), server.URL, headersOf(), NewBytes([]byte("0123456789")), Some(int(4)), Some(Duration(time.Second))), "HttpError_LimitExceeded")
	failedWith(t, n.Request(ctx, get(), server.URL+"/slow", headersOf(), NewBytes(nil), None[int](), Some(Duration(20*time.Millisecond))), "HttpError_Timeout")
	failedWith(t, n.Request(ctx, get(), server.URL, headersOf(), NewBytes(nil), Some(int(-1)), None[Duration]()), "HttpError_InvalidInput")
	failedWith(t, n.Request(ctx, get(), server.URL, headersOf(), NewBytes(nil), None[int](), Some(Duration(-5))), "HttpError_InvalidInput")
	restricted := must(t, n.Restrict(ctx, NewList("example.test"), NewList[string](), false))
	failedWith(t, restricted.Request(ctx, get(), server.URL, headersOf(), NewBytes(nil), None[int](), Some(Duration(time.Second))), "HttpError_PermissionDenied")
	n.Close(ctx)
	failedWith(t, n.Request(ctx, get(), server.URL, headersOf(), NewBytes(nil), None[int](), None[Duration]()), "HttpError_Closed")
}

func TestHttpMethodValidation(t *testing.T) {
	var calls atomic.Int64
	peer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls.Add(1)
		w.Header().Add("X-Method", r.Method)
		w.Header().Add("Set-Cookie", "a=1")
		w.Header().Add("Set-Cookie", "b=2")
	}))
	defer peer.Close()
	ctx, n := newTestNetwork(t)
	client := must(t, n.HttpClient(ctx, clientOptions()))
	for _, token := range []string{"", "BAD METHOD", "bad/name", "é", "x\r\ny"} {
		method := HttpMethod_Custom{Value: token}
		failedWith(t, n.Request(ctx, method, peer.URL, headersOf(), NewBytes(nil), Some(int(10)), Some(Duration(time.Second))), "HttpError_InvalidInput")
		failedWith(t, client.Request(ctx, method, peer.URL, headersOf(), NewBytes(nil), Some(int(10)), Some(Duration(time.Second))), "HttpError_InvalidInput")
		failedWith(t, client.RequestStream(ctx, method, peer.URL, headersOf(), &sliceStream{}, Some(int(10)), Some(Duration(time.Second))), "HttpError_InvalidInput")
	}
	if calls.Load() != 0 {
		t.Fatal("malformed method reached loopback peer")
	}
	response := must(t, client.Request(ctx, HttpMethod_Custom{Value: "CUSTOM"}, peer.URL, headersOf(), NewBytes(nil), Some(int(10)), Some(Duration(time.Second))))
	first := response.Metadata(ctx)
	response.Close(ctx)
	next := response.Metadata(ctx)
	if first != next || next.Status != 200 {
		t.Fatal("closed metadata lost identity")
	}
	if !reflect.DeepEqual(headerValues(next.Headers, "set-cookie"), []string{"a=1", "b=2"}) || !reflect.DeepEqual(headerValues(next.Headers, "x-method"), []string{"CUSTOM"}) {
		t.Fatal("closed metadata lost fields")
	}
}

func assertHeaderMap(t *testing.T, headers *HttpHeaders, want map[string][]string) {
	t.Helper()
	keys := []string{}
	for _, entry := range headers.entries {
		keys = append(keys, entry.name)
		if values, ok := want[entry.name]; ok {
			if got := textOf(entry.values); !reflect.DeepEqual(got, values) {
				t.Errorf("%s: got %q, want %q", entry.name, got, values)
			}
			delete(want, entry.name)
		}
	}
	if !sort.StringsAreSorted(keys) || len(want) != 0 {
		t.Fatalf("keys %q, missing %v", keys, want)
	}
}

func TestHttpClientHeaderCollisions(t *testing.T) {
	ctx, n := newTestNetwork(t)
	client := must(t, n.HttpClient(ctx, clientOptions()))
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header()["X-Dup"] = r.Header.Values("x-dup")
		w.Header().Add("Set-Cookie", "a=1; Expires=Wed, 21 Oct 2037 07:28:00 GMT")
		w.Header().Add("set-cookie", "b=2")
		w.Header().Set("X-Empty", "")
		io.Copy(w, r.Body)
	}))
	defer server.Close()
	for _, kind := range []string{"buffered", "request", "request_stream"} {
		for _, reverse := range []bool{false, true} {
			t.Run(kind+map[bool]string{false: "/forward", true: "/reverse"}[reverse], func(t *testing.T) {
				first, second := "first", "second"
				if reverse {
					first, second = second, first
				}
				headers := headersOf("x-dup", first, "X-Dup", second)
				want := map[string][]string{"X-Dup": {first, second}, "X-Empty": {""}, "Set-Cookie": {"a=1; Expires=Wed, 21 Oct 2037 07:28:00 GMT", "b=2"}}
				if kind == "buffered" {
					response := must(t, n.Request(ctx, post(), server.URL, headers, NewBytes([]byte("ok")), Some(int(10)), Some(Duration(2*time.Second))))
					if str(response.Body) != "ok" {
						t.Fatal(str(response.Body))
					}
					assertHeaderMap(t, response.Head.Headers, want)
					return
				}
				var body ResponseBody
				if kind == "request" {
					body = must(t, client.Request(ctx, post(), server.URL, headers, NewBytes([]byte("ok")), Some(int(10)), Some(Duration(2*time.Second))))
				} else {
					stream := &sliceStream{data: []byte("ok")}
					body = must(t, client.RequestStream(ctx, post(), server.URL, headers, stream, Some(int(10)), Some(Duration(2*time.Second))))
					defer func() {
						if stream.closed {
							t.Error("borrowed upload stream was closed")
						}
					}()
				}
				defer body.Close(ctx)
				if got := someBytes(t, body.Read(ctx, Some(int(10)))); got != "ok" {
					t.Fatal(got)
				}
				assertHeaderMap(t, body.Metadata(ctx).Headers, want)
			})
		}
	}
}

func rawRequest(t *testing.T, address, headers string) *http.Response {
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

func TestHttpBufferedResponseHeaderCollisions(t *testing.T) {
	ctx, n := newTestNetwork(t)
	headers := headersOf("x-dup", "first", "X-Dup", "second", "Set-Cookie", "a=1; Expires=Wed, 21 Oct 2037 07:28:00 GMT", "set-cookie", "b=2", "X-Empty", "", "X-Text", "é\t🙂")
	server := must(t, n.Serve(ctx, "127.0.0.1:0", func(*Execution, *HttpRequest) *HttpResponse {
		return &HttpResponse{Status: 200, Headers: headers, Body: NewBytes([]byte("ok"))}
	}, None[int](), None[int](), None[int](), None[Duration](), None[Duration]()))
	response, err := (&http.Client{Timeout: 2 * time.Second}).Get("http://" + server.Address(ctx))
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	if !reflect.DeepEqual(response.Header.Values("x-dup"), []string{"first", "second"}) || !reflect.DeepEqual(response.Header.Values("SET-cookie"), []string{"a=1; Expires=Wed, 21 Oct 2037 07:28:00 GMT", "b=2"}) {
		t.Fatalf("headers %#v", response.Header)
	}
	if !reflect.DeepEqual(response.Header.Values("X-Empty"), []string{""}) || response.Header.Get("X-Text") != "é\t🙂" {
		t.Fatalf("empty/UTF-8 headers lost: %#v", response.Header)
	}
	if body, _ := io.ReadAll(response.Body); string(body) != "ok" {
		t.Fatal(string(body))
	}
}

func TestHttpReceivedHeadersKeepRawBytes(t *testing.T) {
	ctx, n := newTestNetwork(t)
	seen := make(chan *HttpHeaders, 1)
	buffered := must(t, n.Serve(ctx, "127.0.0.1:0", func(_ *Execution, r *HttpRequest) *HttpResponse {
		seen <- r.Headers
		return &HttpResponse{Status: 200, Headers: headersOf(), Body: NewBytes([]byte("ok"))}
	}, None[int](), None[int](), None[int](), None[Duration](), None[Duration]()))
	rawRequest(t, buffered.Address(ctx), "x-test: first\r\nX-Test: second\r\nX-Raw: \xff\r\n").Body.Close()
	h := <-seen
	if got := headerValues(h, "x-TEST"); !reflect.DeepEqual(got, []string{"first", "second"}) {
		t.Fatal(got)
	}
	if raw := HttpHeaders_Values(ctx, h, "x-raw"); !raw.Some || !reflect.DeepEqual(raw.Val.Items[0].Data, []byte{255}) {
		t.Fatal("raw bytes lost")
	}
	failedWith(t, HttpHeaders_Text(ctx, h, "X-Raw"), "HttpError_InvalidData")
	if host := headerValues(h, "Host"); len(host) != 1 || host[0] != buffered.Address(ctx) {
		t.Fatal("Host not exposed:", host)
	}
	// Streaming servers reject invalid UTF-8 before the handler runs.
	var invoked atomic.Bool
	streaming := must(t, n.ServeStream(ctx, "127.0.0.1:0", func(*Execution, HttpExchange) Result[Unit, HttpError] {
		invoked.Store(true)
		return Ok[Unit, HttpError](Unit{})
	}, serverOptions()))
	response := rawRequest(t, streaming.Address(ctx), "X-Raw: \xff\r\n")
	response.Body.Close()
	if response.StatusCode != 400 || invoked.Load() {
		t.Fatal("streaming request admitted invalid UTF-8", response.StatusCode)
	}
	peer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { w.Header().Set("X-Raw", "\xff") }))
	defer peer.Close()
	failedWith(t, n.Request(ctx, get(), peer.URL, headersOf(), NewBytes(nil), Some(int(10)), Some(Duration(2*time.Second))), "HttpError_InvalidData")
	client := must(t, n.HttpClient(ctx, clientOptions()))
	failedWith(t, client.Request(ctx, get(), peer.URL, headersOf(), NewBytes(nil), Some(int(10)), Some(Duration(2*time.Second))), "HttpError_InvalidData")
}

func TestHttpMalformedIncomingHeaders(t *testing.T) {
	ctx, n := newTestNetwork(t)
	var invoked atomic.Bool
	buffered := must(t, n.Serve(ctx, "127.0.0.1:0", func(*Execution, *HttpRequest) *HttpResponse {
		invoked.Store(true)
		return &HttpResponse{Status: 200, Headers: headersOf(), Body: NewBytes(nil)}
	}, None[int](), None[int](), None[int](), None[Duration](), None[Duration]()))
	streaming := must(t, n.ServeStream(ctx, "127.0.0.1:0", func(*Execution, HttpExchange) Result[Unit, HttpError] {
		invoked.Store(true)
		return Ok[Unit, HttpError](Unit{})
	}, serverOptions()))
	for _, address := range []string{buffered.Address(ctx), streaming.Address(ctx)} {
		for _, header := range []string{"Bad Name: x\r\n", "X-é: x\r\n", "X-Bad: \x00\r\n", "X-Bad: \x01\r\n", "X-Bad: \x7f\r\n", "X-Bad: embedded\rvalue\r\n"} {
			response := rawRequest(t, address, header)
			response.Body.Close()
			if response.StatusCode != 400 || invoked.Load() {
				t.Fatalf("malformed input %q: status %d, handler called %v", header, response.StatusCode, invoked.Load())
			}
		}
	}
}

func TestHttpMalformedOutgoingHeaders(t *testing.T) {
	for _, tc := range []struct{ name, key, value string }{
		{"empty name", "", "ok"}, {"space in name", "X Bad", "ok"}, {"colon in name", "X:Bad", "ok"},
		{"unicode name", "X-é", "ok"},
		{"CR", "X-Bad", "bad\rvalue"}, {"LF", "X-Bad", "bad\nvalue"}, {"NUL", "X-Bad", "bad\x00value"},
		{"control", "X-Bad", "bad\x01value"}, {"DEL", "X-Bad", "bad\x7fvalue"},
		{"invalid UTF-8", "X-Bad", "\xff"},
		{"content length", "cOnTeNt-LeNgTh", "1"}, {"transfer encoding", "TRANSFER-encoding", "chunked"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			ctx, n := newTestNetwork(t)
			out := headersOf("X-Prefix", "validated first", tc.key, tc.value)
			buffered := must(t, n.Serve(ctx, "127.0.0.1:0", func(*Execution, *HttpRequest) *HttpResponse {
				return &HttpResponse{Status: 200, Headers: out, Body: NewBytes([]byte("ok"))}
			}, None[int](), None[int](), None[int](), None[Duration](), None[Duration]()))
			response, err := (&http.Client{Timeout: 2 * time.Second}).Get("http://" + buffered.Address(ctx))
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
			failedWith(t, n.Request(ctx, get(), peer.URL, out, NewBytes(nil), Some(int(10)), Some(Duration(2*time.Second))), "HttpError_InvalidInput")
			client := must(t, n.HttpClient(ctx, clientOptions()))
			failedWith(t, client.Request(ctx, get(), peer.URL, out, NewBytes(nil), Some(int(10)), Some(Duration(2*time.Second))), "HttpError_InvalidInput")
			failedWith(t, client.RequestStream(ctx, get(), peer.URL, out, &sliceStream{}, Some(int(10)), Some(Duration(2*time.Second))), "HttpError_InvalidInput")
			if requests.Load() != 0 {
				t.Fatal("invalid client headers reached peer")
			}
			// A failed send_headers is recoverable and emits none of the valid prefix.
			result := make(chan Result[Unit, HttpError], 1)
			server := must(t, n.ServeStream(ctx, "127.0.0.1:0", func(child *Execution, e HttpExchange) Result[Unit, HttpError] {
				result <- e.SendHeaders(child, 200, headersOf("X-Prefix", "valid", tc.key, tc.value))
				return e.SendHeaders(child, 201, headersOf())
			}, serverOptions()))
			response, err = (&http.Client{Timeout: 2 * time.Second}).Get("http://" + server.Address(ctx))
			if err != nil {
				t.Fatal(err)
			}
			response.Body.Close()
			failedWith(t, <-result, "HttpError_InvalidInput")
			if response.StatusCode != 201 || response.Header.Get("X-Prefix") != "" {
				t.Fatalf("partial invalid streaming headers: %d %#v", response.StatusCode, response.Header)
			}
		})
	}
}

func TestHttpStreamingHeaderCollisions(t *testing.T) {
	ctx, n := newTestNetwork(t)
	server := must(t, n.ServeStream(ctx, "127.0.0.1:0", func(child *Execution, e HttpExchange) Result[Unit, HttpError] {
		forward := &HttpHeaders{}
		for _, entry := range e.Headers(child).entries {
			if !strings.EqualFold(entry.name, "Connection") {
				for _, v := range entry.values.Items {
					forward.add(entry.name, v)
				}
			}
		}
		forward.add("set-cookie", NewBytes([]byte("c=3")))
		forward.add("set-cookie", NewBytes([]byte("d=4")))
		return e.SendHeaders(child, 200, forward)
	}, serverOptions()))
	response := rawRequest(t, server.Address(ctx), "x-dup: first\r\nX-Dup: second\r\nX-Dup: third\r\nX-Empty: \r\nSet-Cookie: a=1\r\nset-cookie: b=2\r\n")
	defer response.Body.Close()
	if response.StatusCode != 200 || !reflect.DeepEqual(response.Header.Values("X-Dup"), []string{"first", "second", "third"}) || !reflect.DeepEqual(response.Header.Values("Set-Cookie"), []string{"a=1", "b=2", "c=3", "d=4"}) || !reflect.DeepEqual(response.Header.Values("X-Empty"), []string{""}) {
		t.Fatalf("streamed headers: %d %#v", response.StatusCode, response.Header)
	}
}

func TestHeadersFromKeepsExactEntries(t *testing.T) {
	// A host map need not have canonical keys; both spellings merge in sorted order.
	headers := http.Header{"x-dup": {"first", ""}, "X-Dup": {"second"}}
	assertHeaderMap(t, headersFrom(headers), map[string][]string{"X-Dup": {"second", "first", ""}})
}

func TestBufferedServerLimitsAndFaults(t *testing.T) {
	ctx, n := newTestNetwork(t)
	entered := make(chan struct{})
	release := make(chan struct{})
	server := must(t, n.Serve(ctx, "127.0.0.1:0", func(_ *Execution, r *HttpRequest) *HttpResponse {
		switch r.Path {
		case "/block":
			entered <- struct{}{}
			<-release
		case "/fault":
			Raise("handler exploded")
		case "/bad-status":
			return &HttpResponse{Status: 99, Headers: headersOf(), Body: NewBytes(nil)}
		case "/big":
			return &HttpResponse{Status: 200, Headers: headersOf(), Body: NewBytes([]byte("0123456789"))}
		}
		return &HttpResponse{Status: 200, Headers: headersOf(), Body: NewBytes([]byte(str(r.Body)))}
	}, Some(int(1)), Some(int(8)), Some(int(5)), Some(Duration(2*time.Second)), Some(Duration(time.Second))))
	address := server.Address(ctx)
	client := &http.Client{Timeout: 3 * time.Second}
	statusOf := func(path, body string) int {
		resp, err := client.Post("http://"+address+path, "text/plain", strings.NewReader(body))
		if err != nil {
			t.Fatal(err)
		}
		resp.Body.Close()
		return resp.StatusCode
	}
	go func() {
		if resp, err := client.Get("http://" + address + "/block"); err == nil {
			resp.Body.Close()
		}
	}()
	<-entered
	if got := statusOf("/", ""); got != 503 {
		t.Fatal("admission limit:", got)
	}
	close(release)
	time.Sleep(50 * time.Millisecond)
	if got := statusOf("/", "123456789"); got != 413 {
		t.Fatal("body limit:", got)
	}
	if got := statusOf("/fault", ""); got != 500 {
		t.Fatal("fault:", got)
	}
	if got := statusOf("/bad-status", ""); got != 500 {
		t.Fatal("invalid status:", got)
	}
	if got := statusOf("/big", ""); got != 500 {
		t.Fatal("response limit:", got)
	}
	if got := statusOf("/", "ok"); got != 200 {
		t.Fatal("ok:", got)
	}
	failedWith(t, n.Serve(ctx, "127.0.0.1:0", nil, Some(int(0)), None[int](), None[int](), None[Duration](), None[Duration]()), "IoError_InvalidInput")
	failedWith(t, n.Serve(ctx, "127.0.0.1:0", nil, None[int](), Some(int(-1)), None[int](), None[Duration](), None[Duration]()), "IoError_InvalidInput")
	failedWith(t, n.Serve(ctx, "not-an-address", nil, None[int](), None[int](), None[int](), None[Duration](), None[Duration]()), "IoError_Unavailable")
	restricted := must(t, n.Restrict(ctx, NewList("localhost"), NewList("127.0.0.0/8"), false))
	failedWith(t, restricted.Serve(ctx, "127.0.0.1:0", nil, None[int](), None[int](), None[int](), None[Duration](), None[Duration]()), "IoError_Unavailable")
	failedWith(t, restricted.ServeStream(ctx, "127.0.0.1:0", nil, serverOptions()), "HttpError_PermissionDenied")
	server.Close(ctx)
	server.Close(ctx)
	if r := server.Wait(ctx); r.Failed {
		t.Fatal("wait after close:", r.Err)
	}
}

func TestServerAndNetworkCannotCloseFromTheirHandler(t *testing.T) {
	ctx, n := newTestNetwork(t)
	faults := make(chan any, 2)
	var server HttpServer
	ready := make(chan struct{})
	server = must(t, n.Serve(ctx, "127.0.0.1:0", func(child *Execution, _ *HttpRequest) *HttpResponse {
		<-ready
		for _, closeIt := range []func(){func() { server.Close(child) }, func() { n.Close(child) }} {
			func() {
				defer func() { faults <- recover() }()
				closeIt()
			}()
		}
		return &HttpResponse{Status: 200, Headers: headersOf(), Body: NewBytes(nil)}
	}, None[int](), None[int](), None[int](), None[Duration](), None[Duration]()))
	close(ready)
	resp, err := (&http.Client{Timeout: 2 * time.Second}).Get("http://" + server.Address(ctx))
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	for _, want := range []string{"HTTP server cannot close from its own request", "network cannot close from its own request"} {
		fault, ok := (<-faults).(Fault)
		if !ok || fault.Message != want {
			t.Fatalf("fault %#v; want %q", fault, want)
		}
	}
}

func TestStreamingServerExchange(t *testing.T) {
	ctx, n := newTestNetwork(t)
	server := must(t, n.ServeStream(ctx, "127.0.0.1:0", func(child *Execution, e HttpExchange) Result[Unit, HttpError] {
		switch e.Path(child) {
		case "/silent":
			return Ok[Unit, HttpError](Unit{})
		case "/domain-error":
			return httpFail[Unit](httpFailed("nope"))
		case "/early-write":
			must(t, e.SendHeaders(child, 200, headersOf()))
			failedWith(t, e.SendHeaders(child, 200, headersOf()), "HttpError_InvalidInput")
			failedWith(t, e.SendHeaders(child, 99, headersOf()), "HttpError_InvalidInput")
			return Ok[Unit, HttpError](Unit{})
		case "/no-headers":
			failedWith(t, e.Write(child, NewBytes([]byte("x"))), "IoError_InvalidInput")
			return Ok[Unit, HttpError](Unit{})
		case "/limit":
			must(t, e.SendHeaders(child, 200, headersOf()))
			failedWith(t, e.Write(child, NewBytes([]byte(strings.Repeat("x", 20)))), "IoError_Failed")
			return Ok[Unit, HttpError](Unit{})
		case "/closed":
			e.Close(child)
			failedWith(t, e.Read(child, None[int]()), "IoError_Closed")
			failedWith(t, e.SendHeaders(child, 200, headersOf()), "HttpError_Closed")
			failedWith(t, e.Write(child, NewBytes(nil)), "IoError_Closed")
			if e.Path(child) != "/closed" || e.Query(child) != "q=1" {
				t.Error("metadata after close")
			}
			if _, ok := e.Method(child).(HttpMethod_Post); !ok {
				t.Error("method after close")
			}
			return Ok[Unit, HttpError](Unit{})
		}
		must(t, e.SendHeaders(child, 200, headersOf()))
		for {
			part := must(t, e.Read(child, Some(int(3))))
			if !part.Some {
				return Ok[Unit, HttpError](Unit{})
			}
			must(t, e.Write(child, part.Val))
		}
	}, &HttpServerOptions{MaxResponseBytes: Some(int(10)), MaxHeaderBytes: Some(int(1024)), Timeout: Some(Duration(3 * time.Second)), Grace: Some(Duration(10 * time.Millisecond))}))
	address := server.Address(ctx)
	client := &http.Client{Timeout: 3 * time.Second}
	status := func(path string) int {
		resp, err := client.Post("http://"+address+path, "text/plain", strings.NewReader("body"))
		if err != nil {
			t.Fatal(path, err)
		}
		resp.Body.Close()
		return resp.StatusCode
	}
	if status("/silent") != 204 || status("/domain-error") != 500 || status("/early-write") != 200 || status("/no-headers") != 204 || status("/limit") != 200 {
		t.Fatal("status mapping")
	}
	// Closing the exchange aborts its transport; the handler still sees Closed errors.
	if resp, err := client.Post("http://"+address+"/closed?q=1", "text/plain", strings.NewReader("body")); err == nil {
		resp.Body.Close()
	}
	// Echo through a streaming upload: the borrowed source is not closed.
	httpClient := must(t, n.HttpClient(ctx, clientOptions()))
	input := &sliceStream{data: []byte("bounded")}
	body := must(t, httpClient.RequestStream(ctx, post(), "http://"+address+"/", headersOf(), input, Some(int(1000)), Some(Duration(time.Second))))
	if got := readAll(t, ctx, body.Read, 4); got != "bounded" || input.closed {
		t.Fatal(got, "borrowed input closed:", input.closed)
	}
	body.Close(ctx)
	failedWith(t, n.ServeStream(ctx, "127.0.0.1:0", nil, &HttpServerOptions{MaxHeaderBytes: Some(int(0))}), "HttpError_InvalidInput")
	failedWith(t, n.ServeStream(ctx, "127.0.0.1:0", nil, &HttpServerOptions{MaxRequests: Some(int(0))}), "HttpError_InvalidInput")
	failedWith(t, n.ServeStream(ctx, "127.0.0.1:0", nil, &HttpServerOptions{Tls: Some(&TlsOptions{})}), "HttpError_InvalidInput")
}

func TestServerShutdownCancelsRequestAfterGrace(t *testing.T) {
	ctx, n := newTestNetwork(t)
	started := make(chan struct{})
	stopped := make(chan struct{})
	server := must(t, n.Serve(ctx, "127.0.0.1:0", func(child *Execution, _ *HttpRequest) *HttpResponse {
		close(started)
		<-child.Context.Done()
		close(stopped)
		CheckCancelled(child)
		return nil
	}, None[int](), None[int](), None[int](), None[Duration](), Some(Duration(10*time.Millisecond))))
	go (&http.Client{Timeout: 3 * time.Second}).Get("http://" + server.Address(ctx))
	<-started
	done := make(chan struct{})
	go func() { server.Close(ctx); close(done) }()
	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("server close did not cancel the request")
	}
	<-stopped
}
