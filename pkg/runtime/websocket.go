package msruntime

import (
	"errors"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/gorilla/websocket"
)

func wsErrorOf(e NetworkError) WebSocketError {
	switch e := e.(type) {
	case NetworkError_Closed:
		return WebSocketError_Closed{}
	case NetworkError_Timeout:
		return WebSocketError_Timeout{}
	case NetworkError_PermissionDenied:
		return WebSocketError_PermissionDenied{}
	case NetworkError_Failed:
		return WebSocketError_Failed(e)
	}
	return WebSocketError_Failed{Message: Errors_Message_NetworkError(nil, e)}
}

var (
	errWSInvalidInput WebSocketError = WebSocketError_InvalidInput{}
	errWSInvalidData  WebSocketError = WebSocketError_InvalidData{}
	errWSLimit        WebSocketError = WebSocketError_LimitExceeded{}
	errWSClosed       WebSocketError = WebSocketError_Closed{}
	errWSDenied       WebSocketError = WebSocketError_PermissionDenied{}
)

// WebSocket opens a client connection to a ws or wss URL.
func (n *osNetwork) WebSocket(ctx *Execution, address string, headers *HttpHeaders, subprotocols *List[string], options *WebSocketOptions) Result[WebSocket, WebSocketError] {
	if options == nil {
		options = &WebSocketOptions{}
	}
	u, err := url.Parse(address)
	max, okMax := optLimit(options.MaxMessageBytes, netUnlimited)
	timeout, okTimeout := optTimeout(options.Timeout)
	if err != nil || u.Host == "" || u.User != nil || u.Scheme != "ws" && u.Scheme != "wss" || !okMax || max <= 0 || !okTimeout {
		return wsFail[WebSocket](errWSInvalidInput)
	}
	if !n.policy.host(u.Hostname()) {
		return wsFail[WebSocket](errWSDenied)
	}
	config, err := originTLSConfig(options.Tls)
	if err != nil {
		return wsFail[WebSocket](errWSInvalidInput)
	}
	protocols := stringItems(subprotocols)
	for _, p := range protocols {
		if !validHeaderName(p) {
			return wsFail[WebSocket](errWSInvalidInput)
		}
	}
	header := http.Header{}
	for _, entry := range headers.entries {
		if !validHeaderName(entry.name) || strings.HasPrefix(strings.ToLower(entry.name), "sec-websocket-") || strings.EqualFold(entry.name, "Upgrade") || strings.EqualFold(entry.name, "Connection") || strings.EqualFold(entry.name, "Host") {
			return wsFail[WebSocket](errWSInvalidInput)
		}
		for _, item := range entry.values.Items {
			value := string(item.Data)
			if !utf8.ValidString(value) || strings.ContainsAny(value, "\r\n\x00") {
				return wsFail[WebSocket](errWSInvalidInput)
			}
			header.Add(entry.name, value)
		}
	}
	local, cancel := timeoutContext(ctx.Context, netDurationOf(timeout))
	defer cancel()
	call, finish, admitted := n.beginCall(local)
	if !admitted {
		return wsFail[WebSocket](errWSClosed)
	}
	defer finish()
	dialer := websocket.Dialer{NetDialContext: n.dial, TLSClientConfig: config, HandshakeTimeout: transportTimeout(timeout), Subprotocols: protocols, EnableCompression: options.Compression, ReadBufferSize: 4096, WriteBufferSize: 4096}
	conn, response, err := dialer.DialContext(call, u.String(), header)
	if response != nil && response.Body != nil {
		response.Body.Close()
	}
	if err != nil {
		return wsFail[WebSocket](wsErrorOf(n.failure(ctx, call, err)))
	}
	resource := newWebSocket(conn, n, max)
	if !n.own(resource) {
		resource.close()
		return wsFail[WebSocket](errWSClosed)
	}
	return Ok[WebSocket, WebSocketError](resource)
}

// Upgrade turns the exchange into a WebSocket session inside the request.
func (e *httpExchange) Upgrade(ctx *Execution, allowedOrigins, subprotocols *List[string], maxMessageBytes Option[int]) Result[WebSocket, WebSocketError] {
	max, ok := optLimit(maxMessageBytes, netUnlimited)
	if !ok || max <= 0 {
		return wsFail[WebSocket](errWSInvalidInput)
	}
	origins := stringItems(allowedOrigins)
	protocols := stringItems(subprotocols)
	for _, p := range protocols {
		if !validHeaderName(p) {
			return wsFail[WebSocket](errWSInvalidInput)
		}
	}
	e.writeGate.mustAcquire(ctx)
	defer e.writeGate.release()
	e.readGate.mustAcquire(ctx)
	defer e.readGate.release()
	e.mu.Lock()
	if e.closed || e.sent || e.upgraded {
		e.mu.Unlock()
		return wsFail[WebSocket](errWSInvalidInput)
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
		// The upgrader already wrote its own error response.
		e.mu.Lock()
		e.rejected = true
		e.mu.Unlock()
		return wsFail[WebSocket](WebSocketError_Failed{Message: describeTransportError(err)})
	}
	resource := newWebSocket(conn, e.owner.owner, max)
	e.mu.Lock()
	e.upgraded = true
	e.websocket = resource
	e.mu.Unlock()
	if !resource.owner.own(resource) {
		resource.close()
		return wsFail[WebSocket](errWSClosed)
	}
	return Ok[WebSocket, WebSocketError](resource)
}

// osWebSocket is a message session with separate read and write gates.
type osWebSocket struct {
	failed      bool
	owner       *osNetwork
	conn        *websocket.Conn
	max         int
	life        lifecycle
	read, write gate
}

var _ WebSocket = (*osWebSocket)(nil)

func newWebSocket(conn *websocket.Conn, owner *osNetwork, max int) *osWebSocket {
	conn.SetReadLimit(int64(max))
	return &osWebSocket{conn: conn, owner: owner, max: max, read: newGate(), write: newGate(), life: newLifecycle()}
}

func (w *osWebSocket) closeResource(*Execution) { w.close() }

func (w *osWebSocket) Close(*Execution) Unit { w.close(); return Unit{} }

// close attempts a normal close frame within a short bounded write deadline,
// then releases the handle and joins admitted operations.
func (w *osWebSocket) close() {
	if !w.life.begin() {
		return
	}
	w.conn.WriteControl(websocket.CloseMessage, websocket.FormatCloseMessage(websocket.CloseNormalClosure, ""), time.Now().Add(100*time.Millisecond))
	w.conn.Close()
	w.life.finish()
	w.owner.forget(w)
}

func (w *osWebSocket) Subprotocol(ctx *Execution) string {
	CheckCancelled(ctx)
	return w.conn.Subprotocol()
}

// admit takes a direction's gate and the activity count.
func (w *osWebSocket) admit(ctx *Execution, g gate) bool {
	g.mustAcquire(ctx)
	w.life.mu.Lock()
	if w.life.closed || w.failed {
		w.life.mu.Unlock()
		g.release()
		return false
	}
	w.life.active.Add(1)
	w.life.mu.Unlock()
	return true
}

func (w *osWebSocket) fail() {
	w.life.mu.Lock()
	w.failed = true
	w.life.mu.Unlock()
}

func (w *osWebSocket) Receive(ctx *Execution) Result[Option[*WebSocketMessage], WebSocketError] {
	if !w.admit(ctx, w.read) {
		return wsFail[Option[*WebSocketMessage]](errWSClosed)
	}
	defer w.read.release()
	defer w.life.leave()
	defer interruptWith(ctx, func() { w.conn.Close() })()
	kind, reader, err := w.conn.NextReader()
	var data []byte
	if err == nil {
		var code string
		data, code = readBounded(ctx, reader, w.max)
		if code != "" {
			if code == "LimitExceeded" {
				err = websocket.ErrReadLimit
			} else {
				err = io.ErrUnexpectedEOF
			}
		}
	}
	if err != nil {
		w.fail()
		w.conn.Close()
	}
	CheckCancelled(ctx)
	if err != nil {
		if websocket.IsCloseError(err, websocket.CloseNormalClosure, websocket.CloseGoingAway) {
			return Ok[Option[*WebSocketMessage], WebSocketError](None[*WebSocketMessage]())
		}
		if w.life.isClosed() {
			return wsFail[Option[*WebSocketMessage]](errWSClosed)
		}
		if errors.Is(err, websocket.ErrReadLimit) {
			return wsFail[Option[*WebSocketMessage]](errWSLimit)
		}
		return wsFail[Option[*WebSocketMessage]](WebSocketError_Failed{Message: describeTransportError(err)})
	}
	text := kind == websocket.TextMessage
	if text && !utf8.Valid(data) {
		// RFC 6455 section 8.1: fail the connection with 1007.
		w.fail()
		w.conn.WriteControl(websocket.CloseMessage, websocket.FormatCloseMessage(websocket.CloseInvalidFramePayloadData, ""), time.Now().Add(100*time.Millisecond))
		w.conn.Close()
		return wsFail[Option[*WebSocketMessage]](errWSInvalidData)
	}
	return Ok[Option[*WebSocketMessage], WebSocketError](Some(&WebSocketMessage{Data: NewBytes(data), Text: text}))
}

func (w *osWebSocket) Ping(ctx *Execution, data string) Result[Unit, WebSocketError] {
	return w.PingBytes(ctx, NewBytes([]byte(data)))
}

func (w *osWebSocket) PingBytes(ctx *Execution, data *Bytes) Result[Unit, WebSocketError] {
	if !w.admit(ctx, w.write) {
		return wsFail[Unit](errWSClosed)
	}
	defer w.write.release()
	defer w.life.leave()
	defer interruptWith(ctx, func() { w.conn.Close() })()
	if len(data.Data) > 125 {
		return wsFail[Unit](errWSInvalidInput)
	}
	err := w.conn.WriteControl(websocket.PingMessage, data.Data, time.Now().Add(time.Second))
	CheckCancelled(ctx)
	if err != nil {
		return wsFail[Unit](WebSocketError_Failed{Message: describeTransportError(err)})
	}
	return Ok[Unit, WebSocketError](Unit{})
}

func (w *osWebSocket) Send(ctx *Execution, data string) Result[Unit, WebSocketError] {
	return w.SendBytes(ctx, NewBytes([]byte(data)), true)
}

func (w *osWebSocket) SendBytes(ctx *Execution, data *Bytes, text bool) Result[Unit, WebSocketError] {
	if !w.admit(ctx, w.write) {
		return wsFail[Unit](errWSClosed)
	}
	defer w.write.release()
	defer w.life.leave()
	defer interruptWith(ctx, func() { w.conn.Close() })()
	if len(data.Data) > w.max {
		return wsFail[Unit](errWSLimit)
	}
	kind := websocket.BinaryMessage
	if text {
		if !utf8.Valid(data.Data) {
			return wsFail[Unit](errWSInvalidData)
		}
		kind = websocket.TextMessage
	}
	err := w.conn.WriteMessage(kind, data.Data)
	CheckCancelled(ctx)
	if err != nil {
		return wsFail[Unit](WebSocketError_Failed{Message: describeTransportError(err)})
	}
	return Ok[Unit, WebSocketError](Unit{})
}
