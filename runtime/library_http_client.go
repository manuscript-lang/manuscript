package msruntime

import (
	"bytes"
	"context"
	"crypto/tls"
	"errors"
	"io"
	"net/http"
	"net/http/cookiejar"
	"net/url"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"golang.org/x/net/publicsuffix"
)

func init() {
	for _, m := range []LibraryMethod{
		{"Network", "http_client", libraryResult("HttpClient"), []LibraryParam{{"options", "HttpClientOptions"}}},
		{"HttpClient", "send", libraryResult("ResponseBody"), []LibraryParam{{"method", "String"}, {"url", "String"}, {"headers", "Map[String][String]"}, {"body", "Bytes"}, {"max_response_bytes", "Int"}, {"timeout", "Duration"}}},
		{"HttpClient", "send_stream", libraryResult("ResponseBody"), []LibraryParam{{"method", "String"}, {"url", "String"}, {"headers", "Map[String][String]"}, {"body", "ReadStream"}, {"max_response_bytes", "Int"}, {"timeout", "Duration"}}},
		{"HttpClient", "close", "Unit", nil},
		{"ResponseBody", "status", "Int", nil}, {"ResponseBody", "headers", "Map[String][List[String]]", nil},
		{"ResponseBody", "read", "Result[Optional[Bytes]][IoError]", []LibraryParam{{"max_bytes", "Int"}}},
		{"ResponseBody", "close", "Unit", nil},
	} {
		LibraryMethods = append(LibraryMethods, m)
	}
}

type libraryHTTPClient struct {
	owner     *network
	client    *http.Client
	transport *http.Transport
	mu        sync.Mutex
	closed    bool
	bodies    map[*libraryResponseBody]bool
	requests  map[*libraryNetworkCall]bool
	active    sync.WaitGroup
	released  chan struct{}
}

func (n *network) httpOperation(name string) (Function, bool) {
	switch name {
	case "web_socket":
		return n.webSocketDial(), true
	case "serve_stream":
		return n.serveStreaming(), true
	case "http_client":
		return libraryAcquisition("Network", name, func(_ *Execution, r string, a []Value) Value {
			f := a[0].(Record).Fields
			redirects, idle, headerMax := f["max_redirects"].(int64), f["max_idle_connections"].(int64), f["max_header_bytes"].(int64)
			idleTimeout := f["idle_timeout"].(Duration)
			if redirects < 0 || idle < 0 || idle > 65536 || headerMax <= 0 || idleTimeout < 0 {
				return libraryError(r, "InvalidInput", "")
			}
			config, err := libraryHTTPClientTLS(f["tls"])
			if err != nil {
				return libraryError(r, "InvalidInput", "")
			}
			config.ServerName = "" // HTTP validates each request's hostname, never a fixed name from a prior origin.
			transport := &http.Transport{DialContext: n.dial, TLSClientConfig: config, ForceAttemptHTTP2: true, MaxResponseHeaderBytes: headerMax, MaxIdleConns: int(idle), MaxIdleConnsPerHost: int(idle), IdleConnTimeout: time.Duration(idleTimeout), DisableCompression: !f["decompress"].(bool)}
			client := &http.Client{Transport: transport}
			if f["cookies"].(bool) {
				client.Jar, _ = cookiejar.New(&cookiejar.Options{PublicSuffixList: publicsuffix.List})
			}
			client.CheckRedirect = func(next *http.Request, previous []*http.Request) error {
				if redirects == 0 {
					return http.ErrUseLastResponse
				}
				if int64(len(previous)) > redirects {
					return errors.New("redirect limit exceeded")
				}
				old := previous[len(previous)-1]
				if old.URL.Scheme == "https" && next.URL.Scheme != "https" {
					return errors.New("TLS downgrade redirect rejected")
				}
				if next.URL.User != nil || next.URL.Scheme != "http" && next.URL.Scheme != "https" || !n.policy.host(next.URL.Hostname()) {
					return osPermissionError()
				}
				if !sameHTTPOrigin(next.URL, old.URL) {
					next.Header.Del("Authorization")
					next.Header.Del("Cookie")
					next.Header.Del("Proxy-Authorization")
				}
				return nil
			}
			resource := &libraryHTTPClient{owner: n, client: client, transport: transport, bodies: map[*libraryResponseBody]bool{}, requests: map[*libraryNetworkCall]bool{}, released: make(chan struct{})}
			if !n.own(resource) {
				transport.CloseIdleConnections()
				return libraryError(r, "Closed", "")
			}
			return libraryOK(r, ViewOf("@std/HttpClient", resource))
		}), true
	}
	return Function{}, false
}
func sameHTTPOrigin(a, b *url.URL) bool {
	return strings.EqualFold(a.Scheme, b.Scheme) && strings.EqualFold(a.Host, b.Host)
}
func osPermissionError() error { return errors.New("network policy denied redirect") }
func (c *libraryHTTPClient) Operation(name string) Function {
	if name == "close" {
		return libraryMethod("HttpClient", name, func(_ *Execution, _ string, _ []Value) Value { c.close(); return Unit{} })
	}
	return libraryAcquisition("HttpClient", name, func(ctx *Execution, r string, a []Value) Value {
		max, timeout := a[4].(int64), a[5].(Duration)
		if max < 0 || timeout < 0 {
			return libraryError(r, "InvalidInput", "")
		}
		u, err := url.Parse(a[1].(string))
		if err != nil || u.Host == "" || u.User != nil || u.Scheme != "http" && u.Scheme != "https" {
			return libraryError(r, "InvalidInput", "")
		}
		if !c.owner.policy.host(u.Hostname()) {
			return libraryError(r, "PermissionDenied", "")
		}
		local, cancel := contextWithLibraryTimeout(ctx, timeout)
		call, networkDone, ok := c.owner.beginCall(local)
		if !ok {
			cancel()
			return libraryError(r, "Closed", "")
		}
		finish := func() { cancel(); networkDone() }
		c.mu.Lock()
		if c.closed {
			c.mu.Unlock()
			finish()
			return libraryError(r, "Closed", "")
		}
		requestCall := &libraryNetworkCall{cancel: cancel}
		c.requests[requestCall] = true
		c.active.Add(1)
		c.mu.Unlock()
		defer func() { c.mu.Lock(); delete(c.requests, requestCall); c.mu.Unlock(); c.active.Done() }()
		delivered := false
		defer func() {
			if !delivered {
				finish()
			}
		}()
		var body io.Reader = nil
		var bridge *libraryStreamReader
		if name != "send_stream" {
			body = bytes.NewReader(a[3].(Bytes).Items)
		}
		if name == "send_stream" {
			bridge = newLibraryStreamReader(inherit(ctx, call), a[3])
			defer func() {
				if !delivered {
					bridge.Close()
				}
			}()
			body = bridge
		}
		req, err := http.NewRequestWithContext(call, a[0].(string), u.String(), body)
		if err != nil {
			return libraryError(r, "InvalidInput", "")
		}
		for _, entry := range a[2].(Map).Entries {
			key, value := entry.Key.(string), entry.Value.(string)
			if !libraryHeaderName(key) || strings.ContainsAny(value, "\r\n\x00") || strings.EqualFold(key, "Host") || strings.EqualFold(key, "Content-Length") || strings.EqualFold(key, "Transfer-Encoding") {
				return libraryError(r, "InvalidInput", "")
			}
			req.Header.Set(key, value)
		}
		// A borrowed streaming body cannot be replayed; return redirects for explicit handling.
		client := *c.client
		if bridge != nil {
			client.CheckRedirect = func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }
		}
		response, err := client.Do(req)
		if bridge != nil {
			bridge.rethrow()
		}
		if err != nil {
			return c.owner.networkFailure(ctx, r, call, err)
		}
		if !libraryHTTPTextHeaders(response.Header) {
			response.Body.Close()
			return libraryError(r, "InvalidData", "")
		}
		resource := &libraryResponseBody{owner: c.owner, client: c, upload: bridge, response: response, reader: response.Body, remaining: max, lifetime: call, finish: finish, gate: make(chan struct{}, 1), released: make(chan struct{})}
		resource.gate <- struct{}{}

		c.owner.mu.Lock()
		c.mu.Lock()
		if c.closed || c.owner.closed {
			c.mu.Unlock()
			c.owner.mu.Unlock()
			response.Body.Close()
			return libraryError(r, "Closed", "")
		}
		c.bodies[resource] = true
		c.owner.resources = append(c.owner.resources, resource)
		c.mu.Unlock()
		c.owner.mu.Unlock()

		delivered = true
		return libraryOK(r, ViewOf("@std/ResponseBody", resource))
	})
}
func (c *libraryHTTPClient) close() {
	c.mu.Lock()
	if c.closed {
		done := c.released
		c.mu.Unlock()
		<-done
		return
	}
	c.closed = true
	for call := range c.requests {
		call.cancel()
	}
	bodies := []*libraryResponseBody{}
	for body := range c.bodies {
		bodies = append(bodies, body)
	}
	c.mu.Unlock()
	for _, body := range bodies {
		body.close()
	}
	c.active.Wait()
	c.transport.CloseIdleConnections()
	c.owner.forgetResource(c)
	close(c.released)
}

type libraryResponseBody struct {
	upload    *libraryStreamReader
	owner     *network
	client    *libraryHTTPClient
	response  *http.Response
	reader    io.ReadCloser
	remaining int64
	mu        sync.Mutex
	closed    bool
	active    sync.WaitGroup
	gate      chan struct{}
	released  chan struct{}
	lifetime  context.Context
	finish    func()
}

func (b *libraryResponseBody) close() {
	b.mu.Lock()
	if b.closed {
		done := b.released
		b.mu.Unlock()
		<-done
		return
	}
	b.closed = true
	b.mu.Unlock()
	b.finish()
	if b.upload != nil {
		b.upload.Close()
	}
	b.response.Body.Close()
	b.active.Wait()
	if b.client != nil {
		b.client.mu.Lock()
		delete(b.client.bodies, b)
		b.client.mu.Unlock()
	}
	b.owner.forgetResource(b)
	close(b.released)
	if b.upload != nil {
		b.upload.rethrow()
	}
}
func (b *libraryResponseBody) Operation(name string) Function {
	return libraryMethod("ResponseBody", name, func(ctx *Execution, r string, a []Value) Value {
		switch name {
		case "status":
			return int64(b.response.StatusCode)
		case "headers":
			return libraryHTTPHeaders(b.response.Header)
		case "close":
			b.close()
			return Unit{}
		}
		max := a[0].(int64)
		if max <= 0 {
			return ioError(r, "InvalidInput", "")
		}
		if max > 65536 {
			max = 65536
		}
		libraryGate(ctx, b.gate)
		defer func() { b.gate <- struct{}{} }()
		b.mu.Lock()
		if b.closed {
			b.mu.Unlock()
			return ioError(r, "Closed", "")
		}
		b.active.Add(1)
		b.mu.Unlock()
		defer b.active.Done()
		if b.remaining < max {
			max = b.remaining + 1
		}
		data := make([]byte, max)
		done := make(chan struct{})
		stop := context.AfterFunc(ctx.Context, func() { defer close(done); b.response.Body.Close() })
		count, err := b.reader.Read(data)
		if b.upload != nil {
			b.upload.rethrow()
		}
		if !stop() {
			<-done
		}
		CheckCancelled(ctx)
		if int64(count) > b.remaining {
			b.response.Body.Close()
			return ioError(r, "Failed", "response body limit exceeded")
		}
		b.remaining -= int64(count)
		if count > 0 {
			return libraryOK(r, optional("@std/Bytes", Bytes{data[:count]}, true))
		}
		if err == io.EOF {
			return libraryOK(r, optional("@std/Bytes", nil, false))
		}
		b.mu.Lock()
		closed := b.closed
		b.mu.Unlock()
		if closed {
			return ioError(r, "Closed", "")
		}
		if err != nil {
			return ioError(r, "Failed", err.Error())
		}
		return ioError(r, "Failed", "empty read without EOF")
	})
}
func libraryHTTPHeaders(headers http.Header) Map {
	out := Map{Type: "@std/Map[String][@std/List[String]]"}
	for _, key := range sortedHeaderNames(headers) {
		out.Entries = append(out.Entries, Entry{key, libraryStrings(headers.Values(key))})
	}
	return out
}

type libraryStreamReader struct {
	ctx       *Execution
	stream    Value
	cancel    context.CancelFunc
	mu        sync.Mutex
	fault     any
	closed    bool
	active    sync.WaitGroup
	remainder []byte
}

func newLibraryStreamReader(ctx *Execution, stream Value) *libraryStreamReader {
	call, cancel := context.WithCancel(ctx.Context)
	return &libraryStreamReader{ctx: inherit(ctx, call), stream: stream, cancel: cancel}
}
func (b *libraryStreamReader) Read(p []byte) (count int, err error) {
	b.mu.Lock()
	if b.closed {
		b.mu.Unlock()
		return 0, io.ErrClosedPipe
	}
	b.active.Add(1)
	b.mu.Unlock()
	defer b.active.Done()
	defer func() {
		if fault := recover(); fault != nil {
			if _, cancelled := fault.(cancelled); !cancelled {
				b.mu.Lock()
				b.fault = fault
				b.mu.Unlock()
			}
			count = 0
			err = context.Canceled
		}
	}()
	if len(p) == 0 {
		return 0, nil
	}
	if len(b.remainder) == 0 {
		v := Invoke(b.ctx, Bind(b.stream, "", "read"), []Argument{{"max_bytes", int64(len(p))}}).(Alternative)
		if v.Tag == "error" {
			return 0, errors.New("source stream read failed")
		}
		part := v.Fields[0].(Alternative)
		if part.Tag == "none" {
			return 0, io.EOF
		}
		b.remainder = part.Fields[0].(Bytes).Items
		if len(b.remainder) == 0 || len(b.remainder) > len(p) {
			return 0, errors.New("source stream violated chunk bound")
		}
	}
	count = copy(p, b.remainder)
	b.remainder = b.remainder[count:]
	return count, nil
}
func (b *libraryStreamReader) Close() error {
	b.mu.Lock()
	b.closed = true
	b.mu.Unlock()
	b.cancel()
	b.active.Wait()
	return nil
}
func (b *libraryStreamReader) rethrow() {
	b.mu.Lock()
	fault := b.fault
	b.mu.Unlock()
	if fault != nil {
		panic(fault)
	}
}

func libraryHTTPClientTLS(value Value) (*tls.Config, error) {
	f := value.(Record).Fields
	copyFields := map[string]Value{}
	for k, v := range f {
		copyFields[k] = v
	}
	copyFields["server_name"] = "origin.invalid"
	config, err := libraryTLSOptions(Record{value.(Record).Type, copyFields}, false)
	if config != nil {
		config.ServerName = ""
	}
	return config, err
}

func libraryHTTPTextHeaders(headers http.Header) bool {
	for key, values := range headers {
		if !utf8.ValidString(key) {
			return false
		}
		for _, value := range values {
			if !utf8.ValidString(value) {
				return false
			}
		}
	}
	return true
}
