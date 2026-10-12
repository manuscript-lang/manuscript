package msruntime

import (
	"context"
	"errors"
	"io"
	"net"
	"net/http"
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
	return NewAcquisition([]string{"address", "handler", "limit", "max_body_bytes", "max_response_bytes", "timeout", "grace"}, result, func(ctx *Execution, args []Value) Value {
		params := []LibraryParam{{"address", "String"}, {"handler", ""}, {"limit", "Optional[Int]"}, {"max_body_bytes", "Optional[Int]"}, {"max_response_bytes", "Optional[Int]"}, {"timeout", "Optional[Duration]"}, {"grace", "Optional[Duration]"}}
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

func (s *httpService) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if s.streaming {
		s.serveStreamingRequest(w, r)
		return
	}
	s.mu.Lock()
	if s.closing {
		s.mu.Unlock()
		http.Error(w, "server closed", http.StatusServiceUnavailable)
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
	data, err := io.ReadAll(http.MaxBytesReader(w, r.Body, s.bodyLimit))
	if err != nil {
		http.Error(w, "invalid or oversized request body", 413)
		return
	}
	headers := &Map{Type: "@std/Map[String][@std/Bytes]"}
	// Header iteration is sorted for stable source-visible insertion order.
	for _, name := range sortedHeaderNames(r.Header) {
		headers.Entries = append(headers.Entries, Entry{name, Bytes{[]byte(strings.Join(r.Header.Values(name), "\n"))}})
	}
	request := Record{"@std/HttpRequest", map[string]Value{"method": r.Method, "path": r.URL.Path, "query": r.URL.RawQuery, "headers": headers, "body": Bytes{data}}}
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
	for _, entry := range record.Fields["headers"].(*Map).Entries {
		key, value := entry.Key.(string), entry.Value.(string)
		if !validHeaderName(key) || strings.ContainsAny(value, "\r\n\x00") || strings.EqualFold(key, "Content-Length") || strings.EqualFold(key, "Transfer-Encoding") || strings.EqualFold(key, "Connection") {
			http.Error(w, "invalid response header", 500)
			return
		}
	}
	for _, entry := range record.Fields["headers"].(*Map).Entries {
		w.Header().Set(entry.Key.(string), entry.Value.(string))
	}
	w.WriteHeader(int(status))
	w.Write(body)
}
func (s *httpService) Operation(name string) Function {
	if name == "address" {
		return NewFunction(nil, "String", func(_ *Execution, _ []Value) Value { return s.listener.Addr().String() })
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
func sortedHeaderNames(headers http.Header) []string {
	names := make([]string, 0, len(headers))
	for name := range headers {
		names = append(names, name)
	}
	sortStrings(names)
	return names
}
func validHeaderName(name string) bool {
	if name == "" {
		return false
	}
	for _, r := range name {
		if !(r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z' || r >= '0' && r <= '9' || strings.ContainsRune("!#$%&'*+-.^_`|~", r)) {
			return false
		}
	}
	return true
}
