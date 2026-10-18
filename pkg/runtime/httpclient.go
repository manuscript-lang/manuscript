package msruntime

import (
	"bytes"
	"context"
	"errors"
	"io"
	"net/http"
	"net/http/cookiejar"
	"net/url"
	"sync"

	"golang.org/x/net/publicsuffix"
)

func httpErrorOf(e NetworkError) HttpError {
	switch e := e.(type) {
	case NetworkError_Closed:
		return errHTTPClosed
	case NetworkError_Timeout:
		return errHTTPTimeout
	case NetworkError_PermissionDenied:
		return errHTTPDenied
	case NetworkError_Failed:
		return httpFailed(e.Message)
	}
	return httpFailed(Errors_Message_NetworkError(nil, e))
}

// httpURL parses an http or https URL with a host, a valid port and no user
// info.
func httpURL(text string) (*url.URL, bool) {
	u, err := url.Parse(text)
	if err != nil || u.Host == "" || u.User != nil || !validPort(u) || u.Scheme != "http" && u.Scheme != "https" {
		return nil, false
	}
	return u, true
}

// Request performs one buffered HTTP request. Redirects are returned, not
// followed, and no cookies or proxy settings apply.
func (n *osNetwork) Request(ctx *Execution, method HttpMethod, address string, headers *HttpHeaders, body string, maxResponseBytes Option[int], timeout Option[Duration]) Result[*ClientResponse, HttpError] {
	return n.RequestBytes(ctx, method, address, headers, NewBytes([]byte(body)), maxResponseBytes, timeout)
}

func (n *osNetwork) RequestBytes(ctx *Execution, method HttpMethod, address string, headers *HttpHeaders, body *Bytes, maxResponseBytes Option[int], timeout Option[Duration]) Result[*ClientResponse, HttpError] {
	if n.isClosed() {
		return httpFail[*ClientResponse](errHTTPClosed)
	}
	token := methodToken(method)
	if !validHeaderName(token) {
		return httpFail[*ClientResponse](errHTTPInvalidInput)
	}
	max, okMax := optLimit(maxResponseBytes, netUnlimited)
	limit, okTimeout := optTimeout(timeout)
	if !okMax || !okTimeout {
		return httpFail[*ClientResponse](errHTTPInvalidInput)
	}
	_, ok := httpURL(address)
	if !ok {
		return httpFail[*ClientResponse](errHTTPInvalidInput)
	}
	local, cancel := timeoutContext(ctx.Context, netDurationOf(limit))
	defer cancel()
	call, finish, admitted := n.beginCall(local)
	if !admitted {
		return httpFail[*ClientResponse](errHTTPClosed)
	}
	defer finish()
	var data []byte
	if body != nil {
		data = body.Data
	}
	req, err := http.NewRequestWithContext(call, token, address, bytes.NewReader(data))
	if err != nil {
		return httpFail[*ClientResponse](errHTTPInvalidInput)
	}
	if !outgoingHeaders(req.Header, headers, "Content-Length", "Transfer-Encoding", "Host") {
		return httpFail[*ClientResponse](errHTTPInvalidInput)
	}
	// No ambient proxy or cookie jar. Redirects go back to the caller.
	transport := &http.Transport{TLSHandshakeTimeout: transportTimeout(limit), MaxResponseHeaderBytes: int64(netUnlimited), DisableCompression: true, DisableKeepAlives: true, DialContext: n.dial}
	defer transport.CloseIdleConnections()
	client := &http.Client{Transport: transport, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
	response, err := client.Do(req)
	CheckCancelled(ctx)
	if err != nil {
		return httpFail[*ClientResponse](httpErrorOf(n.failure(ctx, call, err)))
	}
	defer response.Body.Close()
	payload, code := readBounded(ctx, response.Body, max)
	if code != "" {
		if call.Err() != nil {
			if n.isClosed() {
				return httpFail[*ClientResponse](errHTTPClosed)
			}
			return httpFail[*ClientResponse](errHTTPTimeout)
		}
		switch code {
		case "LimitExceeded":
			return httpFail[*ClientResponse](errHTTPLimit)
		case "InvalidData":
			return httpFail[*ClientResponse](errHTTPInvalidData)
		}
		return httpFail[*ClientResponse](httpFailed(""))
	}
	if !textHeaders(response.Header) {
		return httpFail[*ClientResponse](errHTTPInvalidData)
	}
	return Ok[*ClientResponse, HttpError](&ClientResponse{Head: &HttpResponseMetadata{Status: int(response.StatusCode), Headers: headersFrom(response.Header)}, Body: NewBytes(payload)})
}

// osHTTPClient is a reusable client with connection pooling that dials
// through its network.
type osHTTPClient struct {
	owner     *osNetwork
	client    *http.Client
	transport *http.Transport
	mu        sync.Mutex
	closed    bool
	bodies    map[*osResponseBody]bool
	requests  map[*netCall]bool
	active    sync.WaitGroup
	released  chan struct{}
}

var _ HttpClient = (*osHTTPClient)(nil)

// HttpClient creates a reusable HTTP client owned by this network.
func (n *osNetwork) HttpClient(_ *Execution, options *HttpClientOptions) Result[HttpClient, HttpError] {
	if options == nil {
		options = &HttpClientOptions{}
	}
	redirects, okRedirects := optLimit(options.MaxRedirects, netUnlimited)
	idle, okIdle := optLimit(options.MaxIdleConnections, netUnlimited)
	headerMax, okHeader := optLimit(options.MaxHeaderBytes, netUnlimited)
	idleTimeout, okTimeout := optTimeout(options.IdleTimeout)
	if !okRedirects || !okIdle || !okHeader || !okTimeout || headerMax <= 0 {
		return httpFail[HttpClient](errHTTPInvalidInput)
	}
	config, err := originTLSConfig(options.Tls)
	if err != nil {
		return httpFail[HttpClient](errHTTPInvalidInput)
	}
	if idle == netUnlimited {
		idle = 0
	}
	transport := &http.Transport{DialContext: n.dial, TLSClientConfig: config, ForceAttemptHTTP2: true, MaxResponseHeaderBytes: int64(headerMax), MaxIdleConns: int(idle), MaxIdleConnsPerHost: int(idle), IdleConnTimeout: transportTimeout(idleTimeout), DisableCompression: !options.Decompress}
	client := &http.Client{Transport: transport}
	if options.Cookies {
		client.Jar, _ = cookiejar.New(&cookiejar.Options{PublicSuffixList: publicsuffix.List})
	}
	client.CheckRedirect = func(next *http.Request, previous []*http.Request) error {
		if redirects == 0 {
			return http.ErrUseLastResponse
		}
		if len(previous) > redirects {
			return errors.New("redirect limit exceeded")
		}
		old := previous[len(previous)-1]
		if old.URL.Scheme == "https" && next.URL.Scheme != "https" {
			return errors.New("TLS downgrade redirect rejected")
		}
		if next.URL.User != nil || next.URL.Scheme != "http" && next.URL.Scheme != "https" || !n.policy.host(next.URL.Hostname()) {
			return errors.New("network policy denied redirect")
		}
		if !sameOrigin(next.URL, old.URL) {
			next.Header.Del("Authorization")
			next.Header.Del("Cookie")
			next.Header.Del("Proxy-Authorization")
		}
		return nil
	}
	resource := &osHTTPClient{owner: n, client: client, transport: transport, bodies: map[*osResponseBody]bool{}, requests: map[*netCall]bool{}, released: make(chan struct{})}
	if !n.own(resource) {
		transport.CloseIdleConnections()
		return httpFail[HttpClient](errHTTPClosed)
	}
	return Ok[HttpClient, HttpError](resource)
}

func (c *osHTTPClient) closeResource(*Execution) { c.close() }

func (c *osHTTPClient) Close(*Execution) Unit { c.close(); return Unit{} }

func (c *osHTTPClient) close() {
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
	bodies := []*osResponseBody{}
	for body := range c.bodies {
		bodies = append(bodies, body)
	}
	c.mu.Unlock()
	for _, body := range bodies {
		body.close()
	}
	c.active.Wait()
	c.transport.CloseIdleConnections()
	c.owner.forget(c)
	close(c.released)
}

func (c *osHTTPClient) Request(ctx *Execution, method HttpMethod, address string, headers *HttpHeaders, body string, maxResponseBytes Option[int], timeout Option[Duration]) Result[ResponseBody, HttpError] {
	return c.RequestBytes(ctx, method, address, headers, NewBytes([]byte(body)), maxResponseBytes, timeout)
}

func (c *osHTTPClient) RequestBytes(ctx *Execution, method HttpMethod, address string, headers *HttpHeaders, body *Bytes, maxResponseBytes Option[int], timeout Option[Duration]) Result[ResponseBody, HttpError] {
	var data []byte
	if body != nil {
		data = body.Data
	}
	return c.do(ctx, method, address, headers, bytes.NewReader(data), nil, maxResponseBytes, timeout)
}

func (c *osHTTPClient) RequestStream(ctx *Execution, method HttpMethod, address string, headers *HttpHeaders, body ReadStream, maxResponseBytes Option[int], timeout Option[Duration]) Result[ResponseBody, HttpError] {
	return c.do(ctx, method, address, headers, nil, body, maxResponseBytes, timeout)
}

func (c *osHTTPClient) do(ctx *Execution, method HttpMethod, address string, headers *HttpHeaders, buffered io.Reader, stream ReadStream, maxResponseBytes Option[int], timeout Option[Duration]) Result[ResponseBody, HttpError] {
	max, okMax := optLimit(maxResponseBytes, netUnlimited)
	limit, okTimeout := optTimeout(timeout)
	if !okMax || !okTimeout {
		return httpFail[ResponseBody](errHTTPInvalidInput)
	}
	token := methodToken(method)
	if !validHeaderName(token) {
		return httpFail[ResponseBody](errHTTPInvalidInput)
	}
	u, ok := httpURL(address)
	if !ok {
		return httpFail[ResponseBody](errHTTPInvalidInput)
	}
	if !c.owner.policy.host(u.Hostname()) {
		return httpFail[ResponseBody](errHTTPDenied)
	}
	local, cancel := timeoutContext(ctx.Context, netDurationOf(limit))
	call, networkDone, admitted := c.owner.beginCall(local)
	if !admitted {
		cancel()
		return httpFail[ResponseBody](errHTTPClosed)
	}
	finish := func() { cancel(); networkDone() }
	c.mu.Lock()
	if c.closed {
		c.mu.Unlock()
		finish()
		return httpFail[ResponseBody](errHTTPClosed)
	}
	requestCall := &netCall{cancel: cancel}
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
	var body io.Reader = buffered
	var bridge *streamReader
	if stream != nil {
		bridge = newStreamReader(netChild(ctx, call), stream)
		defer func() {
			if !delivered {
				bridge.Close()
			}
		}()
		body = bridge
	}
	req, err := http.NewRequestWithContext(call, token, u.String(), body)
	if err != nil {
		return httpFail[ResponseBody](errHTTPInvalidInput)
	}
	if !outgoingHeaders(req.Header, headers, "Host", "Content-Length", "Transfer-Encoding") {
		return httpFail[ResponseBody](errHTTPInvalidInput)
	}
	// A borrowed streaming body cannot be replayed; return redirects for
	// explicit handling.
	client := *c.client
	if bridge != nil {
		client.CheckRedirect = func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }
	}
	response, err := client.Do(req)
	if bridge != nil {
		bridge.rethrow()
	}
	if err != nil {
		return httpFail[ResponseBody](httpErrorOf(c.owner.failure(ctx, call, err)))
	}
	if !textHeaders(response.Header) {
		response.Body.Close()
		return httpFail[ResponseBody](errHTTPInvalidData)
	}
	resource := &osResponseBody{owner: c.owner, client: c, upload: bridge, response: response, metadata: &HttpResponseMetadata{Status: int(response.StatusCode), Headers: headersFrom(response.Header)}, reader: response.Body, remaining: max, finish: finish, gate: newGate(), released: make(chan struct{})}
	c.owner.mu.Lock()
	c.mu.Lock()
	if c.closed || c.owner.closed {
		c.mu.Unlock()
		c.owner.mu.Unlock()
		response.Body.Close()
		return httpFail[ResponseBody](errHTTPClosed)
	}
	c.bodies[resource] = true
	c.owner.resources = append(c.owner.resources, resource)
	c.mu.Unlock()
	c.owner.mu.Unlock()
	delivered = true
	return Ok[ResponseBody, HttpError](resource)
}

// osResponseBody streams a response with a byte budget. Metadata stays
// readable after close.
type osResponseBody struct {
	upload    *streamReader
	owner     *osNetwork
	client    *osHTTPClient
	response  *http.Response
	metadata  *HttpResponseMetadata
	reader    io.ReadCloser
	remaining int
	mu        sync.Mutex
	closed    bool
	active    sync.WaitGroup
	gate      gate
	released  chan struct{}
	finish    func()
}

var _ ResponseBody = (*osResponseBody)(nil)

func (b *osResponseBody) closeResource(*Execution) { b.close() }

func (b *osResponseBody) Close(*Execution) Unit { b.close(); return Unit{} }

func (b *osResponseBody) Metadata(ctx *Execution) *HttpResponseMetadata {
	CheckCancelled(ctx)
	return b.metadata
}

func (b *osResponseBody) close() {
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
	b.owner.forget(b)
	close(b.released)
	if b.upload != nil {
		b.upload.rethrow()
	}
}

func (b *osResponseBody) Read(ctx *Execution, maxBytes Option[int]) Result[Option[*Bytes], IoError] {
	max, ok := optLimit(maxBytes, 65536)
	if !ok || max <= 0 {
		return ioFail[Option[*Bytes]](errIoInvalidInput)
	}
	if max > 65536 {
		max = 65536
	}
	b.gate.mustAcquire(ctx)
	defer b.gate.release()
	b.mu.Lock()
	if b.closed {
		b.mu.Unlock()
		return ioFail[Option[*Bytes]](errIoClosed)
	}
	b.active.Add(1)
	b.mu.Unlock()
	defer b.active.Done()
	if b.remaining < max {
		max = b.remaining + 1
	}
	data := make([]byte, max)
	stop := interruptWith(ctx, func() { b.response.Body.Close() })
	count, err := b.reader.Read(data)
	if b.upload != nil {
		b.upload.rethrow()
	}
	stop()
	CheckCancelled(ctx)
	if int(count) > b.remaining {
		b.response.Body.Close()
		return ioFail[Option[*Bytes]](ioFailed("response body limit exceeded"))
	}
	b.remaining -= int(count)
	if count > 0 {
		return Ok[Option[*Bytes], IoError](Some(NewBytes(data[:count])))
	}
	if err == io.EOF {
		return Ok[Option[*Bytes], IoError](None[*Bytes]())
	}
	b.mu.Lock()
	closed := b.closed
	b.mu.Unlock()
	if closed {
		return ioFail[Option[*Bytes]](errIoClosed)
	}
	if err != nil {
		return ioFail[Option[*Bytes]](ioFailed(describeTransportError(err)))
	}
	return ioFail[Option[*Bytes]](ioFailed("empty read without EOF"))
}

// streamReader lends a ReadStream to net/http as a request body. Faults in the
// source are held and rethrown on the requesting task.
type streamReader struct {
	ctx       *Execution
	stream    ReadStream
	cancel    context.CancelFunc
	mu        sync.Mutex
	fault     any
	closed    bool
	active    sync.WaitGroup
	remainder []byte
}

func newStreamReader(ctx *Execution, stream ReadStream) *streamReader {
	call, cancel := context.WithCancel(ctx.Context)
	return &streamReader{ctx: netChild(ctx, call), stream: stream, cancel: cancel}
}

func (b *streamReader) Read(p []byte) (count int, err error) {
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
			if _, stopped := fault.(cancelled); !stopped {
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
		r := b.stream.Read(b.ctx, Some(len(p)))
		if r.Failed {
			return 0, errors.New("source stream read failed")
		}
		if !r.Val.Some {
			return 0, io.EOF
		}
		b.remainder = r.Val.Val.Data
		if len(b.remainder) == 0 || len(b.remainder) > len(p) {
			return 0, errors.New("source stream violated chunk bound")
		}
	}
	count = copy(p, b.remainder)
	b.remainder = b.remainder[count:]
	return count, nil
}

func (b *streamReader) Close() error {
	b.mu.Lock()
	b.closed = true
	b.mu.Unlock()
	b.cancel()
	b.active.Wait()
	return nil
}

func (b *streamReader) rethrow() {
	b.mu.Lock()
	fault := b.fault
	b.mu.Unlock()
	if fault != nil {
		panic(fault)
	}
}
