package msruntime

import (
	"context"
	"errors"
	"io"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"github.com/gorilla/websocket"
)

func init() {
	for _, m := range []LibraryMethod{
		{"Network", "web_socket", libraryResult("WebSocket", "WebSocketError"), []LibraryParam{{"url", "String"}, {"headers", "Map[String][String]"}, {"subprotocols", "List[String]"}, {"options", "WebSocketOptions"}}},
		{"WebSocket", "receive", libraryResult("Optional[WebSocketMessage]", "WebSocketError"), nil},
		{"WebSocket", "send", libraryResult("Unit", "WebSocketError"), []LibraryParam{{"data", "Bytes"}, {"text", "Bool"}}},
		{"WebSocket", "ping", libraryResult("Unit", "WebSocketError"), []LibraryParam{{"data", "Bytes"}}},
		{"WebSocket", "subprotocol", "String", nil}, {"WebSocket", "close", "Unit", nil},
	} {
		LibraryMethods = append(LibraryMethods, m)
	}
}
func (n *network) webSocketDial() Function {
	return libraryAcquisition("Network", "web_socket", func(ctx *Execution, r string, a []Value) Value {
		u, err := url.Parse(a[0].(string))
		f := a[3].(Record).Fields
		max, timeout := f["max_message_bytes"].(int64), f["timeout"].(Duration)
		if err != nil || u.Host == "" || u.User != nil || u.Scheme != "ws" && u.Scheme != "wss" || max <= 0 || timeout <= 0 {
			return libraryError(r, "InvalidInput", "")
		}
		if !n.policy.host(u.Hostname()) {
			return libraryError(r, "PermissionDenied", "")
		}
		config, err := libraryHTTPClientTLS(f["tls"])
		if err != nil {
			return libraryError(r, "InvalidInput", "")
		}
		protocols := libraryStringValues(a[2])
		for _, p := range protocols {
			if !validHeaderName(p) {
				return libraryError(r, "InvalidInput", "")
			}
		}
		headers := http.Header{}
		for _, entry := range a[1].(*Map).Entries {
			key, value := entry.Key.(string), entry.Value.(string)
			if !validHeaderName(key) || strings.ContainsAny(value, "\r\n\x00") || strings.HasPrefix(strings.ToLower(key), "sec-websocket-") || strings.EqualFold(key, "Upgrade") || strings.EqualFold(key, "Connection") || strings.EqualFold(key, "Host") {
				return libraryError(r, "InvalidInput", "")
			}
			headers.Set(key, value)
		}
		local, cancel := contextWithLibraryTimeout(ctx, timeout)
		defer cancel()
		call, finish, ok := n.beginCall(local)
		if !ok {
			return libraryError(r, "Closed", "")
		}
		defer finish()
		dialer := websocket.Dialer{NetDialContext: n.dial, TLSClientConfig: config, HandshakeTimeout: time.Duration(timeout), Subprotocols: protocols, EnableCompression: f["compression"].(bool), ReadBufferSize: 4096, WriteBufferSize: 4096}
		conn, response, err := dialer.DialContext(call, u.String(), headers)
		if response != nil && response.Body != nil {
			response.Body.Close()
		}
		if err != nil {
			return n.networkFailure(ctx, r, call, err)
		}
		resource := newLibraryWebSocket(conn, n, max)
		if !n.own(resource) {
			resource.close()
			return libraryError(r, "Closed", "")
		}
		return libraryOK(r, ViewOf("@std/WebSocket", resource))
	})
}
func (e *libraryHTTPExchange) upgrade() Function {
	return libraryAcquisition("HttpExchange", "upgrade", func(ctx *Execution, r string, a []Value) Value {
		max := a[2].(int64)
		if max <= 0 {
			return libraryError(r, "InvalidInput", "")
		}
		origins := libraryStringValues(a[0])
		protocols := libraryStringValues(a[1])
		for _, p := range protocols {
			if !validHeaderName(p) {
				return libraryError(r, "InvalidInput", "")
			}
		}
		libraryGate(ctx, e.writeGate)
		defer func() { e.writeGate <- struct{}{} }()
		libraryGate(ctx, e.readGate)
		defer func() { e.readGate <- struct{}{} }()
		e.mu.Lock()
		if e.closed || e.sent || e.upgraded {
			e.mu.Unlock()
			return libraryError(r, "InvalidInput", "")
		}
		e.active.Add(1)
		e.mu.Unlock()
		defer e.active.Done()
		upgrader := websocket.Upgrader{ReadBufferSize: 4096, WriteBufferSize: 4096, Subprotocols: protocols, HandshakeTimeout: e.owner.timeout, CheckOrigin: func(r *http.Request) bool {
			origin := r.Header.Get("Origin")
			if origin == "" {
				return true
			}
			u, err := url.Parse(origin)
			if err != nil || u.User != nil || u.Path != "" || u.RawQuery != "" || u.Fragment != "" || u.Scheme != "http" && u.Scheme != "https" {
				return false
			}
			for _, allowed := range origins {
				if allowed == origin {
					return true
				}
			}
			scheme := "http"
			if r.TLS != nil {
				scheme = "https"
			}
			return len(origins) == 0 && u.Scheme == scheme && strings.EqualFold(u.Host, r.Host)
		}}
		conn, err := upgrader.Upgrade(e.writer, e.request, nil)
		if err != nil {
			return libraryError(r, "Failed", err.Error())
		}
		resource := newLibraryWebSocket(conn, e.owner.owner, max)
		e.mu.Lock()
		e.upgraded = true
		e.websocket = resource
		e.mu.Unlock()
		if !resource.owner.own(resource) {
			resource.close()
			return libraryError(r, "Closed", "")
		}
		return libraryOK(r, ViewOf("@std/WebSocket", resource))
	})
}

type libraryWebSocket struct {
	failed      bool
	owner       *network
	conn        *websocket.Conn
	max         int64
	mu          sync.Mutex
	closed      bool
	active      sync.WaitGroup
	read, write chan struct{}
	released    chan struct{}
}

func newLibraryWebSocket(conn *websocket.Conn, owner *network, max int64) *libraryWebSocket {
	conn.SetReadLimit(max)
	w := &libraryWebSocket{conn: conn, owner: owner, max: max, read: make(chan struct{}, 1), write: make(chan struct{}, 1), released: make(chan struct{})}
	w.read <- struct{}{}
	w.write <- struct{}{}
	return w
}
func (w *libraryWebSocket) close() {
	w.mu.Lock()
	if w.closed {
		done := w.released
		w.mu.Unlock()
		<-done
		return
	}
	w.closed = true
	w.mu.Unlock()
	w.conn.WriteControl(websocket.CloseMessage, websocket.FormatCloseMessage(websocket.CloseNormalClosure, ""), time.Now().Add(100*time.Millisecond))
	w.conn.Close()
	w.active.Wait()
	w.owner.forgetResource(w)
	close(w.released)
}
func (w *libraryWebSocket) Operation(name string) Function {
	return libraryMethod("WebSocket", name, func(ctx *Execution, r string, a []Value) Value {
		if name == "close" {
			w.close()
			return Unit{}
		}
		if name == "subprotocol" {
			return w.conn.Subprotocol()
		}
		gate := w.write
		if name == "receive" {
			gate = w.read
		}
		libraryGate(ctx, gate)
		defer func() { gate <- struct{}{} }()
		w.mu.Lock()
		if w.closed || w.failed {
			w.mu.Unlock()
			return libraryError(r, "Closed", "")
		}
		w.active.Add(1)
		w.mu.Unlock()
		defer w.active.Done()
		done := make(chan struct{})
		stop := context.AfterFunc(ctx.Context, func() { defer close(done); w.conn.Close() })
		defer func() {
			if !stop() {
				<-done
			}
		}()
		if name == "receive" {
			kind, reader, err := w.conn.NextReader()
			var data []byte
			if err == nil {
				var code string
				data, code = libraryReadBounded(ctx, reader, w.max)
				if code != "" {
					if code == "LimitExceeded" {
						err = websocket.ErrReadLimit
					} else {
						err = io.ErrUnexpectedEOF
					}
				}
			}
			if err != nil {
				w.mu.Lock()
				w.failed = true
				w.mu.Unlock()
				w.conn.Close()
			}
			CheckCancelled(ctx)
			if err != nil {
				if websocket.IsCloseError(err, websocket.CloseNormalClosure, websocket.CloseGoingAway) {
					return libraryOK(r, optional("@std/WebSocketMessage", nil, false))
				}
				w.mu.Lock()
				closed := w.closed
				w.mu.Unlock()
				if closed {
					return libraryError(r, "Closed", "")
				}
				if errors.Is(err, websocket.ErrReadLimit) {
					return libraryError(r, "LimitExceeded", "")
				}
				return libraryError(r, "Failed", err.Error())
			}
			text := kind == websocket.TextMessage
			if text && !utf8.Valid(data) {
				return libraryError(r, "InvalidData", "")
			}
			return libraryOK(r, optional("@std/WebSocketMessage", Record{"@std/WebSocketMessage", map[string]Value{"data": Bytes{data}, "text": text}}, true))
		}
		data := a[0].(Bytes).Items
		if name == "ping" {
			if len(data) > 125 {
				return libraryError(r, "InvalidInput", "")
			}
			err := w.conn.WriteControl(websocket.PingMessage, data, time.Now().Add(time.Second))
			CheckCancelled(ctx)
			if err != nil {
				return libraryError(r, "Failed", err.Error())
			}
			return libraryOK(r, Unit{})
		}
		if int64(len(data)) > w.max {
			return libraryError(r, "LimitExceeded", "")
		}
		kind := websocket.BinaryMessage
		if a[1].(bool) {
			if !utf8.Valid(data) {
				return libraryError(r, "InvalidData", "")
			}
			kind = websocket.TextMessage
		}
		err := w.conn.WriteMessage(kind, data)
		CheckCancelled(ctx)
		if err != nil {
			return libraryError(r, "Failed", err.Error())
		}
		return libraryOK(r, Unit{})
	})
}
