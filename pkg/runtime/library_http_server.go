//go:build !ms_lean

package msruntime

import (
	"context"
	"io"
	"net"
	"net/http"
	"strings"
	"sync"
	"time"
	"unicode/utf8"
)

func init() {
	LibraryMethods = append(LibraryMethods, []LibraryMethod{
		{"Network", "serve_stream", libraryResult("HttpServer", "HttpError"), []LibraryParam{{"address", "String"}, {"handler", "fn(exchange:HttpExchange)->Result[Unit][HttpError]"}, {"options", "HttpServerOptions"}}},
		{"HttpExchange", "method", "HttpMethod", nil}, {"HttpExchange", "path", "String", nil}, {"HttpExchange", "query", "String", nil}, {"HttpExchange", "headers", "HttpHeaders", nil},
		{"HttpExchange", "read", "Result[Optional[Bytes]][IoError]", []LibraryParam{{"max_bytes", "Optional[Int]"}}},
		{"HttpExchange", "send_headers", libraryResult("Unit", "HttpError"), []LibraryParam{{"status", "Int"}, {"headers", "HttpHeaders"}}},
		{"HttpExchange", "write", "Result[Unit][IoError]", []LibraryParam{{"data", "Bytes"}}},
		{"HttpExchange", "upgrade", libraryResult("WebSocket", "WebSocketError"), []LibraryParam{{"allowed_origins", "List[String]"}, {"subprotocols", "List[String]"}, {"max_message_bytes", "Optional[Int]"}}},
		{"HttpExchange", "close", "Unit", nil},
	}...)
}
func (n *network) serveStreaming() Function {
	return libraryAcquisition("Network", "serve_stream", func(ctx *Execution, r string, a []Value) Value {
		f := a[2].(Record).Fields
		limit, bodyMax, responseMax, headerMax := f["max_requests"].(int64), f["max_body_bytes"].(int64), f["max_response_bytes"].(int64), f["max_header_bytes"].(int64)
		timeout, grace := f["timeout"].(Duration), f["grace"].(Duration)
		if limit <= 0 || bodyMax < 0 || responseMax < 0 || headerMax <= 0 || headerMax > int64(^uint(0)>>1) || timeout < nativeNoTimeout || grace < nativeNoTimeout {
			return libraryError(r, "InvalidInput", "")
		}
		if !n.listenAllowed(a[0].(string)) {
			return libraryError(r, "PermissionDenied", "")
		}
		call, finish, ok := n.beginCall(ctx.Context)
		if !ok {
			return libraryError(r, "Closed", "")
		}
		defer finish()
		listener, err := (&net.ListenConfig{}).Listen(call, "tcp", a[0].(string))
		if err != nil {
			return n.networkFailure(ctx, r, call, err)
		}
		server := &httpService{listener: listener, parent: ctx, owner: n, handler: a[1], admissionLimit: limit, bodyLimit: bodyMax, responseLimit: responseMax, timeout: time.Duration(timeout), grace: time.Duration(grace), done: make(chan struct{}), closed: make(chan struct{}), streaming: true, headerLimit: headerMax}
		server.context, server.cancel = context.WithCancel(ctx.Context)
		server.server = &http.Server{Handler: server, ReadHeaderTimeout: server.timeout, MaxHeaderBytes: nativeHTTPHeaderBytes(headerMax), BaseContext: func(net.Listener) context.Context { return server.context }}
		tlsOption := f["tls"].(Alternative)
		secure := tlsOption.Tag == "some"
		if secure {
			config, err := libraryTLSOptions(tlsOption.Fields[0], true)
			if err != nil {
				listener.Close()
				server.cancel()
				return libraryError(r, "InvalidInput", "")
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
			return libraryError(r, "Closed", "")
		}
		n.servers = append(n.servers, server)
		n.mu.Unlock()
		registerResource(ctx, server)
		markConcurrent()
		go func() {
			if secure {
				server.err = server.server.ServeTLS(listener, "", "")
			} else {
				server.err = server.server.Serve(listener)
			}
			close(server.done)
		}()
		return libraryOK(r, ViewOf("@std/HttpServer", server))
	})
}

type libraryHTTPExchange struct {
	owner                         *httpService
	request                       *http.Request
	headers                       *libraryHeaders
	writer                        http.ResponseWriter
	ctx                           *Execution
	mu                            sync.Mutex
	closed, sent, upgraded        bool
	rejected                      bool
	readGate, writeGate           chan struct{}
	active                        sync.WaitGroup
	remainingRead, remainingWrite int64
	status                        int64
	websocket                     *libraryWebSocket
}

func (s *httpService) serveStreamingRequest(w http.ResponseWriter, r *http.Request) {
	if !utf8.ValidString(r.URL.Path) || !utf8.ValidString(r.URL.RawQuery) || !libraryHTTPTextHeaders(r.Header) {
		http.Error(w, "invalid UTF-8 request", 400)
		return
	}
	if !normalizeHTTPRequestPath(r) {
		http.Error(w, "invalid request path", 400)
		return
	}
	s.mu.Lock()
	if s.closing {
		s.mu.Unlock()
		http.Error(w, "server closed", 503)
		return
	}
	if s.admissionLimit != nativeUnlimited && s.admitted >= s.admissionLimit {
		s.mu.Unlock()
		http.Error(w, "server busy", 503)
		return
	}
	s.admitted++
	s.requests.Add(1)
	s.mu.Unlock()
	defer s.requests.Done()
	defer func() { s.mu.Lock(); s.admitted--; s.mu.Unlock() }()

	call, cancel := nativeContextTimeout(r.Context(), s.timeout)
	defer cancel()
	child := newExecution(s.parent, call)
	child.HostServices = map[*httpService]bool{s: true}
	for key, value := range s.parent.HostServices {
		child.HostServices[key] = value
	}
	exchange := &libraryHTTPExchange{owner: s, request: r, headers: libraryHTTPHeaders(r.Header), writer: w, ctx: child, remainingRead: s.bodyLimit, remainingWrite: s.responseLimit, readGate: make(chan struct{}, 1), writeGate: make(chan struct{}, 1)}
	exchange.readGate <- struct{}{}
	exchange.writeGate <- struct{}{}
	controller := http.NewResponseController(w)
	controller.EnableFullDuplex()
	if s.timeout >= 0 {
		controller.SetReadDeadline(time.Now().Add(s.timeout))
		controller.SetWriteDeadline(time.Now().Add(s.timeout))
	}
	stop := context.AfterFunc(s.context, cancel)
	defer stop()
	// Hijacked WebSocket connections are not owned by net/http Shutdown. The request
	// lifetime closes them explicitly and the request WaitGroup joins their handlers.
	done := make(chan struct{})
	interrupt := context.AfterFunc(call, func() { defer close(done); exchange.interrupt() })
	defer func() {
		if !interrupt() {
			<-done
		}
		exchange.close()
	}()
	var failure any
	var outcome Value
	func() {
		defer func() { failure = recover() }()
		defer FinishExecution(child)
		outcome = Invoke(child, s.handler, []Argument{{"exchange", ViewOf("@std/HttpExchange", exchange)}})
	}()
	exchange.mu.Lock()
	sent, upgraded, rejected := exchange.sent, exchange.upgraded, exchange.rejected
	exchange.mu.Unlock()
	if failure != nil || call.Err() != nil || outcome.(Alternative).Tag == "error" {
		if failure != nil {
			if _, ok := failure.(cancelled); !ok {
				reportDiagnostic("HTTP stream handler fault: " + fmtFault(failure))
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
func (e *libraryHTTPExchange) interrupt() {
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
func (e *libraryHTTPExchange) close() {
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
func (e *libraryHTTPExchange) Operation(name string) Function {
	if name == "upgrade" {
		return e.upgrade()
	}
	return libraryMethod("HttpExchange", name, func(ctx *Execution, r string, a []Value) Value {
		switch name {
		case "method":
			return libraryHTTPMethod(e.request.Method)
		case "path":
			return e.request.URL.Path
		case "query":
			return e.request.URL.RawQuery
		case "headers":
			return e.headers
		case "close":
			e.interrupt()
			e.close()
			return Unit{}
		}
		gate := e.writeGate
		if name == "read" {
			gate = e.readGate
		}
		libraryGate(ctx, gate)
		defer func() { gate <- struct{}{} }()
		e.mu.Lock()
		if e.closed || e.upgraded || e.rejected {
			e.mu.Unlock()
			if name == "send_headers" {
				return libraryError(r, "Closed", "")
			}
			return ioError(r, "Closed", "")
		}
		e.active.Add(1)
		e.mu.Unlock()
		defer e.active.Done()
		CheckCancelled(e.ctx)
		if name == "read" {
			max := a[0].(int64)
			if max <= 0 {
				return ioError(r, "InvalidInput", "")
			}
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
			if int64(n) > e.remainingRead {
				return ioError(r, "Failed", "request body limit exceeded")
			}
			e.remainingRead -= int64(n)
			if n > 0 {
				return libraryOK(r, optional("@std/Bytes", Bytes{buffer[:n]}, true))
			}
			if err == io.EOF {
				return libraryOK(r, optional("@std/Bytes", nil, false))
			}
			if err != nil {
				return ioError(r, "Failed", err.Error())
			}
			return ioError(r, "Failed", "empty request read")
		}
		if name == "send_headers" {
			status := a[0].(int64)
			e.mu.Lock()
			sent := e.sent
			e.mu.Unlock()
			if sent || status < 200 || status > 599 {
				return libraryError(r, "InvalidInput", "")
			}
			headerBytes := int64(0)
			for _, entry := range a[1].(*libraryHeaders).Entries {
				key := entry.Key.(string)
				if !libraryHeaderName(key) || strings.EqualFold(key, "Content-Length") || strings.EqualFold(key, "Transfer-Encoding") || strings.EqualFold(key, "Connection") {
					return libraryError(r, "InvalidInput", "")
				}
				for _, item := range entry.Value.(*List).Items {
					value := string(item.(Bytes).Items)
					headerBytes += int64(len(key)) + int64(len(value)) + 4
					if headerBytes > e.owner.headerLimit {
						return libraryError(r, "LimitExceeded", "")
					}
					if !validHeaderValue(value) {
						return libraryError(r, "InvalidInput", "")
					}
				}
			}
			for _, entry := range a[1].(*libraryHeaders).Entries {
				for _, item := range entry.Value.(*List).Items {
					value := string(item.(Bytes).Items)
					e.writer.Header().Add(entry.Key.(string), value)
				}
			}
			e.mu.Lock()
			e.sent = true
			e.status = status
			e.mu.Unlock()
			e.writer.WriteHeader(int(status))
			return libraryOK(r, Unit{})
		}
		e.mu.Lock()
		sent, status := e.sent, e.status
		e.mu.Unlock()
		if !sent {
			return ioError(r, "InvalidInput", "")
		}
		data := a[0].(Bytes).Items
		if int64(len(data)) > e.remainingWrite {
			return ioError(r, "Failed", "response body limit exceeded")
		}
		if e.request.Method == "HEAD" || status == 204 || status == 304 {
			return ioError(r, "InvalidInput", "")
		}
		n, err := e.writer.Write(data)
		e.remainingWrite -= int64(n)
		if err == nil && n != len(data) {
			err = io.ErrShortWrite
		}
		if err == nil {
			err = http.NewResponseController(e.writer).Flush()
		}
		CheckCancelled(ctx)
		CheckCancelled(e.ctx)
		if err != nil {
			return ioError(r, "Failed", err.Error())
		}
		return libraryOK(r, Unit{})
	})
}
