package msruntime

import (
	"io"
	"net/http"
	"net/http/httptest"
	"reflect"
	"sync/atomic"
	"testing"
	"time"
)

func TestNormalizeHTTPRequestPath(t *testing.T) {
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
		ok := normalizeHTTPRequestPath(r)
		if want == "" {
			if ok {
				t.Errorf("%s accepted as %q", target, r.URL.Path)
			}
		} else if !ok || r.URL.Path != want {
			t.Errorf("%s: got %q %v, want %q", target, r.URL.Path, ok, want)
		}
	}
}

func TestHTTPPathContractLoopback(t *testing.T) {
	for _, streaming := range []bool{false, true} {
		t.Run(map[bool]string{false: "buffered", true: "streaming"}[streaming], func(t *testing.T) {
			ctx := RootExecution()
			n := &network{}
			defer n.Operation("close").Body(ctx, nil)
			var calls atomic.Int64
			makeHeaders := func(path, query string, lists bool) *libraryHeaders {
				headers := httpTestHeaders(&Map{Type: "@std/Map[String][String]", Entries: []Entry{
					{"X-Path", path}, {"X-Query", query},
					{"x-dup", "first"}, {"X-Dup", "second"},
					{"Set-Cookie", "a=1"}, {"set-cookie", "b=2"},
				}})
				return headers
			}
			var address string
			if streaming {
				handler := NewFunction([]string{"exchange"}, "@std/Result[Unit][@std/HttpError]", func(child *Execution, a []Value) Value {
					calls.Add(1)
					path := networkingInvoke(child, a[0], "path").(string)
					query := networkingInvoke(child, a[0], "query").(string)
					return networkingInvoke(child, a[0], "send_headers", int64(200), makeHeaders(path, query, true))
				})
				server := librarySuccess(t, n.Operation("serve_stream").Body(ctx, []Value{"127.0.0.1:0", handler, networkingServerOptions()}))
				address = networkingInvoke(ctx, server, "address").(string)
			} else {
				handler := NewFunction([]string{"request"}, "@std/HttpResponse", func(_ *Execution, a []Value) Value {
					calls.Add(1)
					request := a[0].(Record)
					response := hostResponse(200, "ok").(Record)
					response.Fields["headers"] = makeHeaders(request.Fields["path"].(string), request.Fields["query"].(string), false)
					return response
				})
				address = serveTest(t, ctx, handler, 1024).listener.Addr().String()
			}
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
					t.Error("#257 header values lost after path normalization", response.Header)
				}
			}
		})
	}
}

func TestHTTPInvalidPortsAllClients(t *testing.T) {
	ctx := RootExecution()
	n := &network{}
	defer n.Operation("close").Body(ctx, nil)
	client := librarySuccess(t, n.Operation("http_client").Body(ctx, []Value{networkingClientOptions()}))
	for _, address := range []string{"http://127.0.0.1:99999/", "http://127.0.0.1:65536/", "http://127.0.0.1:99999999999999999999999/", "http://127.0.0.1:-1/", "http://[::1"} {
		args := []Value{libraryHTTPMethod("GET"), address, httpTestHeaders(&Map{Type: "@std/Map[String][String]"}), Bytes{}, int64(100), Duration(time.Second)}
		libraryFailure(t, n.Operation("request").Body(ctx, args), "InvalidInput")
		libraryFailure(t, networkingInvoke(ctx, client, "request", args...), "InvalidInput")
		args[3] = ViewOf("@std/ReadStream", &networkingReadStream{})
		libraryFailure(t, networkingInvoke(ctx, client, "request_stream", args...), "InvalidInput")
	}
}
