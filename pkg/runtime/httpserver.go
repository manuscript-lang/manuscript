package msruntime

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"
	"unicode/utf8"
)

// servedKey marks the execution of a request handler: the context holds the
// chain of servers whose requests the handler is running inside, so a server
// or network cannot be closed from its own handler.
type servedKey struct{}

type servedChain struct {
	server *httpServer
	next   *servedChain
}

func withServed(c context.Context, s *httpServer) context.Context {
	prev, _ := c.Value(servedKey{}).(*servedChain)
	return context.WithValue(c, servedKey{}, &servedChain{s, prev})
}

func inService(ctx *Execution, match func(*httpServer) bool) bool {
	for c, _ := ctx.Context.Value(servedKey{}).(*servedChain); c != nil; c = c.next {
		if match(c.server) {
			return true
		}
	}
	return false
}

// netReportDiagnostic writes a runtime diagnostic that no caller can receive.
func netReportDiagnostic(message string) { fmt.Fprintln(os.Stderr, message) }

type httpServer struct {
	mu                       sync.Mutex
	streaming                bool
	headerLimit              int
	listener                 net.Listener
	server                   *http.Server
	parent                   *Execution
	owner                    *osNetwork
	context                  context.Context
	cancel                   context.CancelFunc
	handler                  func(*Execution, *HttpRequest) *HttpResponse
	stream                   func(*Execution, HttpExchange) Result[Unit, HttpError]
	admissionLimit           int
	admitted                 int
	bodyLimit, responseLimit int
	timeout, grace           time.Duration
	done, closed             chan struct{}
	err                      error
	closing                  bool
	fault                    any
	requests                 sync.WaitGroup
}

var _ HttpServer = (*httpServer)(nil)

// Serve starts a server whose handler receives each fully buffered request.
func (n *osNetwork) Serve(ctx *Execution, address string, handler func(*Execution, *HttpRequest) *HttpResponse, maxRequests, maxBodyBytes, maxResponseBytes Option[int], timeout, grace Option[Duration]) Result[HttpServer, IoError] {
	limit, ok1 := optLimit(maxRequests, netUnlimited)
	bodyLimit, ok2 := optLimit(maxBodyBytes, netUnlimited)
	responseLimit, ok3 := optLimit(maxResponseBytes, netUnlimited)
	timeLimit, ok4 := optTimeout(timeout)
	graceLimit, ok5 := optTimeout(grace)
	if !(ok1 && ok2 && ok3 && ok4 && ok5) || limit <= 0 {
		return ioFail[HttpServer](errIoInvalidInput)
	}
	call, finish, admitted := n.beginCall(ctx.Context)
	if !admitted {
		return ioFail[HttpServer](errIoClosed)
	}
	defer finish()
	if !n.listenAllowed(address) {
		return ioFail[HttpServer](IoError_Unavailable{})
	}
	listener, err := (&net.ListenConfig{}).Listen(call, "tcp", address)
	if err != nil {
		return ioFail[HttpServer](IoError_Unavailable{})
	}
	server := &httpServer{listener: listener, parent: ctx, owner: n, handler: handler, admissionLimit: limit, bodyLimit: bodyLimit, responseLimit: responseLimit, timeout: time.Duration(timeLimit), grace: time.Duration(graceLimit), done: make(chan struct{}), closed: make(chan struct{})}
	server.context, server.cancel = context.WithCancel(ctx.Context)
	server.server = &http.Server{Handler: server, ReadHeaderTimeout: server.timeout, MaxHeaderBytes: headerBytesLimit(netUnlimited), BaseContext: func(net.Listener) context.Context { return server.context }}
	n.mu.Lock()
	if n.closed {
		n.mu.Unlock()
		listener.Close()
		server.cancel()
		return ioFail[HttpServer](errIoClosed)
	}
	n.servers = append(n.servers, server)
	n.mu.Unlock()
	go func() { server.err = server.server.Serve(listener); close(server.done) }()
	return Ok[HttpServer, IoError](server)
}

// ServeStream starts a server whose handler receives each request as a
// streaming exchange.
func (n *osNetwork) ServeStream(ctx *Execution, address string, handler func(*Execution, HttpExchange) Result[Unit, HttpError], options *HttpServerOptions) Result[HttpServer, HttpError] {
	if options == nil {
		options = &HttpServerOptions{}
	}
	limit, ok1 := optLimit(options.MaxRequests, netUnlimited)
	bodyMax, ok2 := optLimit(options.MaxBodyBytes, netUnlimited)
	responseMax, ok3 := optLimit(options.MaxResponseBytes, netUnlimited)
	headerMax, ok4 := optLimit(options.MaxHeaderBytes, netUnlimited)
	timeout, ok5 := optTimeout(options.Timeout)
	grace, ok6 := optTimeout(options.Grace)
	if !(ok1 && ok2 && ok3 && ok4 && ok5 && ok6) || limit <= 0 || headerMax <= 0 {
		return httpFail[HttpServer](errHTTPInvalidInput)
	}
	if !n.listenAllowed(address) {
		return httpFail[HttpServer](errHTTPDenied)
	}
	call, finish, admitted := n.beginCall(ctx.Context)
	if !admitted {
		return httpFail[HttpServer](errHTTPClosed)
	}
	defer finish()
	listener, err := (&net.ListenConfig{}).Listen(call, "tcp", address)
	if err != nil {
		return httpFail[HttpServer](httpErrorOf(n.failure(ctx, call, err)))
	}
	server := &httpServer{listener: listener, parent: ctx, owner: n, stream: handler, admissionLimit: limit, bodyLimit: bodyMax, responseLimit: responseMax, timeout: time.Duration(timeout), grace: time.Duration(grace), done: make(chan struct{}), closed: make(chan struct{}), streaming: true, headerLimit: headerMax}
	server.context, server.cancel = context.WithCancel(ctx.Context)
	server.server = &http.Server{Handler: server, ReadHeaderTimeout: server.timeout, MaxHeaderBytes: headerBytesLimit(headerMax), BaseContext: func(net.Listener) context.Context { return server.context }}
	secure := options.Tls.Some
	if secure {
		config, err := tlsConfig(options.Tls.Val, true)
		if err != nil {
			listener.Close()
			server.cancel()
			return httpFail[HttpServer](errHTTPInvalidInput)
		}
		if len(config.NextProtos) == 0 {
			config.NextProtos = []string{"h2", "http/1.1"}
		}
		server.server.TLSConfig = config
	}
	n.mu.Lock()
	if n.closed {
		n.mu.Unlock()
		listener.Close()
		server.cancel()
		return httpFail[HttpServer](errHTTPClosed)
	}
	n.servers = append(n.servers, server)
	n.mu.Unlock()
	go func() {
		if secure {
			server.err = server.server.ServeTLS(listener, "", "")
		} else {
			server.err = server.server.Serve(listener)
		}
		close(server.done)
	}()
	return Ok[HttpServer, HttpError](server)
}

// admit pairs with release. Admission and closing share the mutex so shutdown
// cannot begin waiting before an admitted request is counted.
func (s *httpServer) admit(w http.ResponseWriter) bool {
	s.mu.Lock()
	if s.closing {
		s.mu.Unlock()
		http.Error(w, "server closed", http.StatusServiceUnavailable)
		return false
	}
	if s.admissionLimit != netUnlimited && s.admitted >= s.admissionLimit {
		s.mu.Unlock()
		http.Error(w, "server busy", http.StatusServiceUnavailable)
		return false
	}
	s.admitted++
	s.requests.Add(1)
	s.mu.Unlock()
	return true
}

func (s *httpServer) release() {
	s.mu.Lock()
	s.admitted--
	s.mu.Unlock()
	s.requests.Done()
}

func (s *httpServer) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if s.streaming {
		s.serveStreaming(w, r)
		return
	}
	if !s.admit(w) {
		return
	}
	defer s.release()
	call, cancel := timeoutContext(r.Context(), s.timeout)
	defer cancel()
	controller := http.NewResponseController(w)
	if s.timeout >= 0 {
		controller.SetReadDeadline(time.Now().Add(s.timeout))
		controller.SetWriteDeadline(time.Now().Add(s.timeout))
	}
	if !utf8.ValidString(r.URL.Path) || !utf8.ValidString(r.URL.RawQuery) {
		http.Error(w, "invalid UTF-8 URL", 400)
		return
	}
	if !normalizeRequestPath(r) {
		http.Error(w, "invalid request path", 400)
		return
	}
	data, err := io.ReadAll(http.MaxBytesReader(w, r.Body, int64(s.bodyLimit)))
	if err != nil {
		http.Error(w, "invalid or oversized request body", 413)
		return
	}
	request := &HttpRequest{Method: methodOf(r.Method), Path: r.URL.Path, Query: r.URL.RawQuery, Headers: headersFrom(requestHeaders(r)), Body: NewBytes(data)}
	var response *HttpResponse
	var failure any
	func() {
		defer func() { failure = recover() }()
		child := netChild(s.parent, withServed(call, s))
		response = s.handler(child, request)
	}()
	if failure != nil || call.Err() != nil {
		if _, stopped := failure.(cancelled); stopped || call.Err() != nil {
			http.Error(w, "request cancelled", 504)
		} else {
			netReportDiagnostic("HTTP handler fault: " + fmt.Sprint(failure))
			http.Error(w, "handler fault", 500)
		}
		return
	}
	if response == nil || response.Status < 200 || response.Status > 599 || int(len(responseBody(response))) > s.responseLimit {
		http.Error(w, "invalid response", 500)
		return
	}
	headers := response.Headers
	if headers == nil {
		headers = &HttpHeaders{}
	}
	for _, entry := range headers.entries {
		if !validHeaderName(entry.name) || strings.EqualFold(entry.name, "Content-Length") || strings.EqualFold(entry.name, "Transfer-Encoding") || strings.EqualFold(entry.name, "Connection") {
			http.Error(w, "invalid response header", 500)
			return
		}
		for _, value := range entry.values.Items {
			if !validHeaderValue(string(value.Data)) {
				http.Error(w, "invalid response header", 500)
				return
			}
		}
	}
	for _, entry := range headers.entries {
		for _, value := range entry.values.Items {
			w.Header().Add(entry.name, string(value.Data))
		}
	}
	w.WriteHeader(int(response.Status))
	w.Write(responseBody(response))
}

func responseBody(r *HttpResponse) []byte {
	if r.Body == nil {
		return nil
	}
	return r.Body.Data
}

func (s *httpServer) Address(ctx *Execution) string {
	CheckCancelled(ctx)
	v := s.listener.Addr().String()
	CheckCancelled(ctx)
	return v
}

// Wait blocks until the server stops serving.
func (s *httpServer) Wait(ctx *Execution) Result[Unit, IoError] {
	select {
	case <-s.done:
		if s.err != nil && s.err != http.ErrServerClosed {
			return ioFail[Unit](ioFailed(s.err.Error()))
		}
		return Ok[Unit, IoError](Unit{})
	case <-ctx.Context.Done():
		CheckCancelled(ctx)
		return Ok[Unit, IoError](Unit{})
	}
}

func (s *httpServer) closeResource(ctx *Execution) { s.Close(ctx) }

// Close stops accepting, waits up to the grace period for in-flight requests,
// then cancels the rest and joins them.
func (s *httpServer) Close(ctx *Execution) Unit {
	if inService(ctx, func(o *httpServer) bool { return o == s }) {
		Raise("HTTP server cannot close from its own request")
	}
	s.mu.Lock()
	if s.closing {
		done := s.closed
		s.mu.Unlock()
		<-done
		if s.fault != nil {
			panic(s.fault)
		}
		return Unit{}
	}
	s.closing = true
	s.mu.Unlock()
	grace, cancel := timeoutContext(context.Background(), s.grace)
	shutdownError := s.server.Shutdown(grace)
	cancel()
	s.cancel()
	closeError := s.server.Close()
	for _, failure := range []error{shutdownError, closeError} {
		if failure != nil && failure != context.DeadlineExceeded && failure != context.Canceled && failure != http.ErrServerClosed && !errors.Is(failure, net.ErrClosed) {
			if primary, ok := s.fault.(Fault); ok {
				primary.Secondary = append(primary.Secondary, failure.Error())
				s.fault = primary
			} else {
				s.fault = Fault{Message: failure.Error()}
			}
		}
	}
	<-s.done
	s.requests.Wait()
	s.owner.mu.Lock()
	for i, server := range s.owner.servers {
		if server == s {
			copy(s.owner.servers[i:], s.owner.servers[i+1:])
			last := len(s.owner.servers) - 1
			s.owner.servers[last] = nil
			s.owner.servers = s.owner.servers[:last]
			break
		}
	}
	s.owner.mu.Unlock()
	close(s.closed)
	if s.fault != nil {
		panic(s.fault)
	}
	return Unit{}
}

// httpExchange belongs to one request: aliases report Closed once request
// cleanup ends. Read and write have separate gates.
type httpExchange struct {
	owner                         *httpServer
	request                       *http.Request
	headers                       *HttpHeaders
	writer                        http.ResponseWriter
	ctx                           *Execution
	mu                            sync.Mutex
	closed, sent, upgraded        bool
	rejected                      bool
	readGate, writeGate           gate
	active                        sync.WaitGroup
	remainingRead, remainingWrite int
	status                        int
	websocket                     *osWebSocket
}

var _ HttpExchange = (*httpExchange)(nil)

func (s *httpServer) serveStreaming(w http.ResponseWriter, r *http.Request) {
	if !utf8.ValidString(r.URL.Path) || !utf8.ValidString(r.URL.RawQuery) || !textHeaders(r.Header) {
		http.Error(w, "invalid UTF-8 request", 400)
		return
	}
	if !normalizeRequestPath(r) {
		http.Error(w, "invalid request path", 400)
		return
	}
	if !s.admit(w) {
		return
	}
	defer s.release()
	call, cancel := timeoutContext(r.Context(), s.timeout)
	defer cancel()
	child := netChild(s.parent, withServed(call, s))
	exchange := &httpExchange{owner: s, request: r, headers: headersFrom(requestHeaders(r)), writer: w, ctx: child, remainingRead: s.bodyLimit, remainingWrite: s.responseLimit, readGate: newGate(), writeGate: newGate()}
	controller := http.NewResponseController(w)
	controller.EnableFullDuplex()
	if s.timeout >= 0 {
		controller.SetReadDeadline(time.Now().Add(s.timeout))
		controller.SetWriteDeadline(time.Now().Add(s.timeout))
	}
	stop := context.AfterFunc(s.context, cancel)
	defer stop()
	// Hijacked WebSocket connections are not owned by net/http Shutdown. The
	// request lifetime closes them explicitly and the request WaitGroup joins
	// their handlers.
	done := make(chan struct{})
	interrupt := context.AfterFunc(call, func() { defer close(done); exchange.interrupt() })
	defer func() {
		if !interrupt() {
			<-done
		}
		exchange.close()
	}()
	var failure any
	var outcome Result[Unit, HttpError]
	func() {
		defer func() { failure = recover() }()
		outcome = s.stream(child, exchange)
	}()
	exchange.mu.Lock()
	sent, upgraded, rejected := exchange.sent, exchange.upgraded, exchange.rejected
	exchange.mu.Unlock()
	if failure != nil || call.Err() != nil || outcome.Failed {
		if failure != nil {
			if _, stopped := failure.(cancelled); !stopped {
				netReportDiagnostic("HTTP stream handler fault: " + fmt.Sprint(failure))
			}
		}
		if !sent && !upgraded && !rejected {
			status := 500
			if call.Err() != nil {
				status = 504
			}
			http.Error(w, "request failed", status)
		} else if !upgraded && !rejected {
			panic(http.ErrAbortHandler)
		}
		return
	}
	if !sent && !upgraded && !rejected {
		w.WriteHeader(204)
	}
}

func (e *httpExchange) interrupt() {
	e.request.Body.Close()
	controller := http.NewResponseController(e.writer)
	controller.SetReadDeadline(time.Now())
	controller.SetWriteDeadline(time.Now())
	e.mu.Lock()
	socket := e.websocket
	e.mu.Unlock()
	if socket != nil {
		socket.close()
	}
}

func (e *httpExchange) close() {
	e.mu.Lock()
	e.closed = true
	socket := e.websocket
	e.mu.Unlock()
	e.request.Body.Close()
	if socket != nil {
		socket.close()
	}
	e.active.Wait()
}

func (e *httpExchange) Close(*Execution) Unit {
	e.interrupt()
	e.close()
	return Unit{}
}

func (e *httpExchange) Headers(ctx *Execution) *HttpHeaders {
	CheckCancelled(ctx)
	return e.headers
}

func (e *httpExchange) Method(ctx *Execution) HttpMethod {
	CheckCancelled(ctx)
	return methodOf(e.request.Method)
}

func (e *httpExchange) Path(ctx *Execution) string {
	CheckCancelled(ctx)
	return e.request.URL.Path
}

func (e *httpExchange) Query(ctx *Execution) string {
	CheckCancelled(ctx)
	return e.request.URL.RawQuery
}

// admitIO takes a gate and the exchange's activity count.
func (e *httpExchange) admitIO(ctx *Execution, g gate) bool {
	g.mustAcquire(ctx)
	e.mu.Lock()
	if e.closed || e.upgraded || e.rejected {
		e.mu.Unlock()
		g.release()
		return false
	}
	e.active.Add(1)
	e.mu.Unlock()
	return true
}

func (e *httpExchange) leaveIO(g gate) {
	e.active.Done()
	g.release()
}

func (e *httpExchange) Read(ctx *Execution, maxBytes Option[int]) Result[Option[*Bytes], IoError] {
	max, ok := optLimit(maxBytes, 65536)
	if !ok || max <= 0 {
		return ioFail[Option[*Bytes]](errIoInvalidInput)
	}
	if !e.admitIO(ctx, e.readGate) {
		return ioFail[Option[*Bytes]](errIoClosed)
	}
	defer e.leaveIO(e.readGate)
	CheckCancelled(e.ctx)
	if max > 65536 {
		max = 65536
	}
	if e.remainingRead < max {
		max = e.remainingRead + 1
	}
	buffer := make([]byte, max)
	n, err := e.request.Body.Read(buffer)
	CheckCancelled(ctx)
	CheckCancelled(e.ctx)
	if int(n) > e.remainingRead {
		return ioFail[Option[*Bytes]](ioFailed("request body limit exceeded"))
	}
	e.remainingRead -= int(n)
	if n > 0 {
		return Ok[Option[*Bytes], IoError](Some(NewBytes(buffer[:n])))
	}
	if err == io.EOF {
		return Ok[Option[*Bytes], IoError](None[*Bytes]())
	}
	if err != nil {
		return ioFail[Option[*Bytes]](ioFailed(describeTransportError(err)))
	}
	return ioFail[Option[*Bytes]](ioFailed("empty request read"))
}

func (e *httpExchange) SendHeaders(ctx *Execution, status int, headers *HttpHeaders) Result[Unit, HttpError] {
	if !e.admitIO(ctx, e.writeGate) {
		return httpFail[Unit](errHTTPClosed)
	}
	defer e.leaveIO(e.writeGate)
	CheckCancelled(e.ctx)
	e.mu.Lock()
	sent := e.sent
	e.mu.Unlock()
	if sent || status < 200 || status > 599 {
		return httpFail[Unit](errHTTPInvalidInput)
	}
	headerBytes := 0
	for _, entry := range headers.entries {
		if !validHeaderName(entry.name) || strings.EqualFold(entry.name, "Content-Length") || strings.EqualFold(entry.name, "Transfer-Encoding") || strings.EqualFold(entry.name, "Connection") {
			return httpFail[Unit](errHTTPInvalidInput)
		}
		for _, item := range entry.values.Items {
			value := string(item.Data)
			headerBytes += len(entry.name) + len(value) + 4
			if headerBytes > e.owner.headerLimit {
				return httpFail[Unit](errHTTPLimit)
			}
			if !validHeaderValue(value) {
				return httpFail[Unit](errHTTPInvalidInput)
			}
		}
	}
	for _, entry := range headers.entries {
		for _, item := range entry.values.Items {
			e.writer.Header().Add(entry.name, string(item.Data))
		}
	}
	e.mu.Lock()
	e.sent = true
	e.status = status
	e.mu.Unlock()
	e.writer.WriteHeader(int(status))
	return Ok[Unit, HttpError](Unit{})
}

func (e *httpExchange) Write(ctx *Execution, data *Bytes) Result[Unit, IoError] {
	if !e.admitIO(ctx, e.writeGate) {
		return ioFail[Unit](errIoClosed)
	}
	defer e.leaveIO(e.writeGate)
	CheckCancelled(e.ctx)
	e.mu.Lock()
	sent, status := e.sent, e.status
	e.mu.Unlock()
	if !sent {
		return ioFail[Unit](errIoInvalidInput)
	}
	if len(data.Data) > e.remainingWrite {
		return ioFail[Unit](ioFailed("response body limit exceeded"))
	}
	if e.request.Method == "HEAD" || status == 204 || status == 304 {
		return ioFail[Unit](errIoInvalidInput)
	}
	n, err := e.writer.Write(data.Data)
	e.remainingWrite -= int(n)
	if err == nil && n != len(data.Data) {
		err = io.ErrShortWrite
	}
	if err == nil {
		err = http.NewResponseController(e.writer).Flush()
	}
	CheckCancelled(ctx)
	CheckCancelled(e.ctx)
	if err != nil {
		return ioFail[Unit](ioFailed(describeTransportError(err)))
	}
	return Ok[Unit, IoError](Unit{})
}
