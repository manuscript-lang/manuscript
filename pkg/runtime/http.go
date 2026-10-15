//go:build !ms_lean

package msruntime

import (
	"context"
	"errors"
	"io"
	"net"
	"net/http"
	"path"
	"strings"
	"sync"
	"time"
	"unicode/utf8"
)

type network struct {
	mu        sync.Mutex
	policy    *networkPolicy
	resolver  *net.Resolver
	parent    *network
	released  chan struct{}
	servers   []*httpService
	resources []Value
	closed    bool
	calls     map[*libraryNetworkCall]bool
	active    sync.WaitGroup
}

func (n *network) Operation(name string) Function {
	if fn, ok := n.extendedOperation(name); ok {
		return fn
	}
	if fn, ok := n.httpOperation(name); ok {
		return fn
	}
	if name == "connect" || name == "connect_tls" || name == "listen" || name == "bind_datagram" {
		return libraryNetworkAcquire(n, name)
	}
	if name == "request" {
		return libraryMethod("Network", name, func(ctx *Execution, r string, a []Value) Value { return libraryNetworkRequest(n, ctx, r, a) })
	}
	if name == "lookup" {
		return libraryMethod("Network", name, func(ctx *Execution, r string, a []Value) Value { return libraryNetworkLookup(n, ctx, r, a) })
	}
	if name == "close" {
		return NewFunction(nil, "Unit", func(ctx *Execution, _ []Value) Value {
			for service := range ctx.HostServices {
				if service.owner == n {
					Panic("network cannot close from its own request")
				}
			}
			n.mu.Lock()
			if n.closed {
				done := n.released
				n.mu.Unlock()
				if done != nil {
					<-done
				}
				return Unit{}
			}
			n.closed = true
			n.released = make(chan struct{})
			defer close(n.released)
			if n.parent != nil {
				defer n.parent.forgetResource(n)
			}
			servers := append([]*httpService{}, n.servers...)
			resources := append([]Value{}, n.resources...)
			for call := range n.calls {
				call.cancel()
			}
			n.mu.Unlock()
			stack := NewCleanupStack()
			defer n.active.Wait()
			defer stack.Unwind()
			for _, resource := range resources {
				stack.Push(ctx, resource)
			}
			for _, server := range servers {
				stack.Push(ctx, server)
			}
			return Unit{}
		})
	}
	result := "@std/Result[@std/HttpServer][@std/IoError]"
	return NewAcquisition([]string{"address", "handler", "max_requests", "max_body_bytes", "max_response_bytes", "timeout", "grace"}, result, func(ctx *Execution, args []Value) Value {
		params := []LibraryParam{{"address", "String"}, {"handler", ""}, {"max_requests", "Optional[Int]"}, {"max_body_bytes", "Optional[Int]"}, {"max_response_bytes", "Optional[Int]"}, {"timeout", "Optional[Duration]"}, {"grace", "Optional[Duration]"}}
		normalized, valid := nativeOptions("serve", params, args)
		if !valid {
			return ioError(result, "InvalidInput", "")
		}
		args = normalized
		limit, bodyLimit, responseLimit := args[2].(int64), args[3].(int64), args[4].(int64)
		timeout, grace := args[5].(Duration), args[6].(Duration)
		if limit <= 0 || limit > int64(^uint(0)>>1) || bodyLimit < 0 || responseLimit < 0 || timeout < nativeNoTimeout || grace < nativeNoTimeout {
			return ioError(result, "InvalidInput", "")
		}
		call, finish, admitted := n.beginCall(ctx.Context)
		if !admitted {
			return ioError(result, "Closed", "")
		}
		defer finish()
		if !n.listenAllowed(args[0].(string)) {
			return ioError(result, "Unavailable", "")
		}
		listener, err := (&net.ListenConfig{}).Listen(call, "tcp", args[0].(string))
		if err != nil {
			return ioError(result, "Unavailable", "")
		}
		server := &httpService{listener: listener, parent: ctx, owner: n, handler: args[1], admissionLimit: limit, bodyLimit: bodyLimit, responseLimit: responseLimit, timeout: time.Duration(timeout), grace: time.Duration(grace), done: make(chan struct{}), closed: make(chan struct{})}
		server.context, server.cancel = context.WithCancel(ctx.Context)
		server.server = &http.Server{Handler: server, ReadHeaderTimeout: server.timeout, MaxHeaderBytes: nativeHTTPHeaderBytes(nativeUnlimited), BaseContext: func(net.Listener) context.Context { return server.context }}
		n.mu.Lock()
		if n.closed {
			n.mu.Unlock()
			listener.Close()
			server.cancel()
			return ioError(result, "Closed", "")
		}
		n.servers = append(n.servers, server)
		n.mu.Unlock()
		registerResource(ctx, server)
		markConcurrent()
		go func() { server.err = server.server.Serve(listener); close(server.done) }()
		return Alternative{result, "ok", []Value{ViewOf("@std/HttpServer", server)}}
	}, func(ctx *Execution, value Value) {
		result := value.(Alternative)
		if result.Tag == "ok" {
			Invoke(Shield(ctx), Bind(result.Fields[0], "", "close"), nil)
		}
	})
}

type httpService struct {
	mu                       sync.Mutex
	streaming                bool
	headerLimit              int64
	listener                 net.Listener
	server                   *http.Server
	parent                   *Execution
	owner                    *network
	context                  context.Context
	cancel                   context.CancelFunc
	handler                  Value
	admissionLimit           int64
	admitted                 int64
	bodyLimit, responseLimit int64
	timeout, grace           time.Duration
	done, closed             chan struct{}
	err                      error
	closing                  bool
	fault                    any
	requests                 sync.WaitGroup
}

// admitRequest pairs with releaseRequest. Admission and closing share the mutex
// so shutdown cannot begin waiting before an admitted request is counted.
func (s *httpService) admitRequest(w http.ResponseWriter) bool {
	s.mu.Lock()
	if s.closing {
		s.mu.Unlock()
		http.Error(w, "server closed", http.StatusServiceUnavailable)
		return false
	}
	if s.admissionLimit != nativeUnlimited && s.admitted >= s.admissionLimit {
		s.mu.Unlock()
		http.Error(w, "server busy", http.StatusServiceUnavailable)
		return false
	}
	s.admitted++
	s.requests.Add(1)
	s.mu.Unlock()
	return true
}

func (s *httpService) releaseRequest() {
	s.mu.Lock()
	s.admitted--
	s.mu.Unlock()
	s.requests.Done()
}

func (s *httpService) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if s.streaming {
		s.serveStreamingRequest(w, r)
		return
	}
	if !s.admitRequest(w) {
		return
	}
	defer s.releaseRequest()

	execution, cancel := nativeContextTimeout(r.Context(), s.timeout)
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
	if !normalizeHTTPRequestPath(r) {
		http.Error(w, "invalid request path", 400)
		return
	}
	data, err := io.ReadAll(http.MaxBytesReader(w, r.Body, s.bodyLimit))
	if err != nil {
		http.Error(w, "invalid or oversized request body", 413)
		return
	}
	headers := libraryHTTPHeaders(requestHeaders(r))
	request := Record{"@std/HttpRequest", map[string]Value{"method": libraryHTTPMethod(r.Method), "path": r.URL.Path, "query": r.URL.RawQuery, "headers": headers, "body": Bytes{data}}}
	var response Value
	var failure any
	func() {
		defer func() { failure = recover() }()
		child := newExecution(s.parent, execution)
		child.HostServices = map[*httpService]bool{}
		for service, owned := range s.parent.HostServices {
			child.HostServices[service] = owned
		}
		child.HostServices[s] = true
		defer FinishExecution(child)
		response = Invoke(child, s.handler, []Argument{{"request", request}})
	}()
	if failure != nil || execution.Err() != nil {
		if _, stopped := failure.(cancelled); stopped || execution.Err() != nil {
			http.Error(w, "request cancelled", 504)
		} else {
			reportDiagnostic("HTTP handler fault: " + fmtFault(failure))
			http.Error(w, "handler fault", 500)
		}
		return
	}
	record := response.(Record)
	status := record.Fields["status"].(int64)
	body := record.Fields["body"].(Bytes).Items
	if status < 200 || status > 599 || int64(len(body)) > s.responseLimit {
		http.Error(w, "invalid response", 500)
		return
	}
	headers = record.Fields["headers"].(*libraryHeaders)
	for _, entry := range headers.Entries {
		key := entry.Key.(string)
		if !validHeaderName(key) || strings.EqualFold(key, "Content-Length") || strings.EqualFold(key, "Transfer-Encoding") || strings.EqualFold(key, "Connection") {
			http.Error(w, "invalid response header", 500)
			return
		}
		for _, value := range entry.Value.(*List).Items {
			if !validHeaderValue(string(value.(Bytes).Items)) {
				http.Error(w, "invalid response header", 500)
				return
			}
		}
	}
	for _, entry := range headers.Entries {
		for _, value := range entry.Value.(*List).Items {
			w.Header().Add(entry.Key.(string), string(value.(Bytes).Items))
		}
	}
	w.WriteHeader(int(status))
	w.Write(body)
}
func (s *httpService) Operation(name string) Function {
	if name == "address" {
		Panic("read-only accessor address is not a method")
	}
	if name == "wait" {
		result := "@std/Result[Unit][@std/IoError]"
		return NewFunction(nil, result, func(ctx *Execution, _ []Value) Value {
			select {
			case <-s.done:
				if s.err != nil && s.err != http.ErrServerClosed {
					return ioError(result, "Failed", s.err.Error())
				}
				return Alternative{result, "ok", []Value{Unit{}}}
			case <-ctx.Context.Done():
				CheckCancelled(ctx)
				return Unit{}
			}
		})
	}
	return NewFunction(nil, "Unit", func(ctx *Execution, _ []Value) Value { s.close(ctx); return Unit{} })
}
func (s *httpService) close(ctx *Execution) {
	if ctx.HostServices[s] {
		Panic("HTTP server cannot close from its own request")
	}
	s.mu.Lock()
	if s.closing {
		done := s.closed
		s.mu.Unlock()
		<-done
		if s.fault != nil {
			panic(s.fault)
		}
		return
	}
	s.closing = true
	s.mu.Unlock()
	grace, cancel := nativeContextTimeout(context.Background(), s.grace)
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
	unregisterResource(s.parent, s)
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
}

// requestHeaders returns the request headers including Host, which net/http
// moves out of Header into Request.Host.
func requestHeaders(r *http.Request) http.Header {
	headers := r.Header.Clone()
	if headers == nil {
		headers = http.Header{}
	}
	if r.Host != "" {
		headers.Set("Host", r.Host)
	}
	return headers
}
func sortedHeaderNames(headers http.Header) []string {
	names := make([]string, 0, len(headers))
	for name := range headers {
		names = append(names, name)
	}
	sortStrings(names)
	return names
}

// normalizeHTTPRequestPath makes the decoded path safe to route on: an
// encoded slash or NUL is rejected, and dot segments (including encoded ones)
// are resolved so no spelling can climb above the root.
func normalizeHTTPRequestPath(r *http.Request) bool {
	raw := r.URL.EscapedPath()
	if strings.Contains(raw, "%00") || strings.Contains(strings.ToLower(raw), "%2f") || strings.Contains(r.URL.Path, "\x00") {
		return false
	}
	if strings.HasPrefix(r.URL.Path, "/") {
		clean := path.Clean(r.URL.Path)
		if strings.HasSuffix(r.URL.Path, "/") && clean != "/" {
			clean += "/"
		}
		r.URL.Path, r.URL.RawPath = clean, ""
	}
	return true
}

// Source header values are UTF-8 text. HTTP permits HTAB, visible bytes and
// non-ASCII text, but no other control bytes or DEL.
func validHeaderValue(value string) bool {
	if !utf8.ValidString(value) {
		return false
	}
	for i := range len(value) {
		if value[i] < 32 && value[i] != '\t' || value[i] == 127 {
			return false
		}
	}
	return true
}
