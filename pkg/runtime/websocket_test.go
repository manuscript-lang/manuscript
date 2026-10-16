package msruntime

import (
	"log"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/gorilla/websocket"
)

type logSink func([]byte) (int, error)

func (f logSink) Write(p []byte) (int, error) { return f(p) }

func upgradeHandler(t *testing.T, max int, protocols ...string) func(*Execution, HttpExchange) Result[Unit, HttpError] {
	return func(child *Execution, e HttpExchange) Result[Unit, HttpError] {
		upgraded := e.Upgrade(child, NewList[string](), NewList(protocols...), Some(max))
		if upgraded.Failed { // the test already finished and closed the network
			return Ok[Unit, HttpError](Unit{})
		}
		socket := upgraded.Val
		if message := must(t, socket.Receive(child)); message.Some {
			must(t, socket.Send(child, message.Val.Data, message.Val.Text))
		}
		return Ok[Unit, HttpError](Unit{})
	}
}

func TestWebSocketEchoAndStreamingUpload(t *testing.T) {
	ctx, n := newTestNetwork(t)
	server := must(t, n.ServeStream(ctx, "127.0.0.1:0", upgradeHandler(t, 32, "echo"), serverOptions()))
	address := server.Address(ctx)
	socket := must(t, n.WebSocket(ctx, "ws://"+address+"/ws", headersOf("X-Token", "t"), NewList("echo"), wsOptions(32, false)))
	if socket.Subprotocol(ctx) != "echo" {
		t.Fatal("subprotocol", socket.Subprotocol(ctx))
	}
	must(t, socket.Send(ctx, NewBytes([]byte("hello")), true))
	message := must(t, socket.Receive(ctx))
	if !message.Some || str(message.Val.Data) != "hello" || !message.Val.Text {
		t.Fatalf("%+v", message)
	}
	// After the handler returns, the server closes the session.
	if closed := socket.Receive(ctx); closed.Failed || closed.Val.Some {
		t.Fatalf("expected a normal end of stream, got %+v", closed)
	}
	socket.Close(ctx)
	socket.Close(ctx)
	failedWith(t, socket.Receive(ctx), "WebSocketError_Closed")
	failedWith(t, socket.Send(ctx, NewBytes(nil), false), "WebSocketError_Closed")
	failedWith(t, socket.Ping(ctx, NewBytes(nil)), "WebSocketError_Closed")
	if socket.Subprotocol(ctx) != "echo" {
		t.Fatal("subprotocol after close")
	}
	server.Close(ctx)
}

func TestWebSocketSendValidationAndPing(t *testing.T) {
	ctx, n := newTestNetwork(t)
	release := make(chan struct{})
	server := must(t, n.ServeStream(ctx, "127.0.0.1:0", func(child *Execution, e HttpExchange) Result[Unit, HttpError] {
		upgraded := e.Upgrade(child, NewList[string](), NewList[string](), None[int]())
		if upgraded.Failed { // the test already finished and closed the network
			return Ok[Unit, HttpError](Unit{})
		}
		socket := upgraded.Val
		<-release
		socket.Close(child)
		return Ok[Unit, HttpError](Unit{})
	}, serverOptions()))
	defer close(release)
	socket := must(t, n.WebSocket(ctx, "ws://"+server.Address(ctx), headersOf(), NewList[string](), wsOptions(8, false)))
	failedWith(t, socket.Send(ctx, NewBytes([]byte("123456789")), false), "WebSocketError_LimitExceeded")
	failedWith(t, socket.Send(ctx, NewBytes([]byte{0xff}), true), "WebSocketError_InvalidData")
	must(t, socket.Send(ctx, NewBytes([]byte{0xff}), false))
	failedWith(t, socket.Ping(ctx, NewBytes(make([]byte, 126))), "WebSocketError_InvalidInput")
	must(t, socket.Ping(ctx, NewBytes([]byte("p"))))
}

func TestWebSocketDialValidation(t *testing.T) {
	ctx, n := newTestNetwork(t)
	good := wsOptions(8, false)
	for _, address := range []string{"http://127.0.0.1:1/", "ws://", "ws://user@127.0.0.1:1/", "not a url\x7f"} {
		failedWith(t, n.WebSocket(ctx, address, headersOf(), NewList[string](), good), "WebSocketError_InvalidInput")
	}
	for _, name := range []string{"Upgrade", "connection", "HOST", "Sec-WebSocket-Key", "bad name"} {
		failedWith(t, n.WebSocket(ctx, "ws://127.0.0.1:1/", headersOf(name, "x"), NewList[string](), good), "WebSocketError_InvalidInput")
	}
	failedWith(t, n.WebSocket(ctx, "ws://127.0.0.1:1/", headersOf("X", "a\r\nb"), NewList[string](), good), "WebSocketError_InvalidInput")
	failedWith(t, n.WebSocket(ctx, "ws://127.0.0.1:1/", headersOf(), NewList("bad protocol"), good), "WebSocketError_InvalidInput")
	failedWith(t, n.WebSocket(ctx, "ws://127.0.0.1:1/", headersOf(), NewList[string](), wsOptions(0, false)), "WebSocketError_InvalidInput")
	failedWith(t, n.WebSocket(ctx, "ws://127.0.0.1:1/", headersOf(), NewList[string](), &WebSocketOptions{Timeout: Some(Duration(-1))}), "WebSocketError_InvalidInput")
	failedWith(t, n.WebSocket(ctx, "ws://127.0.0.1:1/", headersOf(), NewList[string](), &WebSocketOptions{Tls: &TlsOptions{RootsPem: "junk"}}), "WebSocketError_InvalidInput")
	failedWith(t, n.WebSocket(ctx, "ws://127.0.0.1:1/", headersOf(), NewList[string](), good), "WebSocketError_Failed")
	restricted := must(t, n.Restrict(ctx, NewList("example.test"), NewList[string](), false))
	failedWith(t, restricted.WebSocket(ctx, "ws://127.0.0.1:1/", headersOf(), NewList[string](), good), "WebSocketError_PermissionDenied")
	n.Close(ctx)
	failedWith(t, n.WebSocket(ctx, "ws://127.0.0.1:1/", headersOf(), NewList[string](), good), "WebSocketError_Closed")
}

func TestWebSocketRejectedUpgradeWritesOneResponse(t *testing.T) {
	var logs strings.Builder
	var mu sync.Mutex
	log.SetOutput(logSink(func(p []byte) (int, error) { mu.Lock(); defer mu.Unlock(); return logs.Write(p) }))
	defer log.SetOutput(os.Stderr)
	ctx, n := newTestNetwork(t)
	server := must(t, n.ServeStream(ctx, "127.0.0.1:0", func(child *Execution, e HttpExchange) Result[Unit, HttpError] {
		if r := e.Upgrade(child, NewList[string](), NewList[string](), Some(int(32))); !r.Failed {
			t.Error("plain request upgraded")
		}
		return Ok[Unit, HttpError](Unit{})
	}, serverOptions()))
	response, err := http.Get("http://" + server.Address(ctx) + "/")
	if err != nil {
		t.Fatal(err)
	}
	response.Body.Close()
	if response.StatusCode != 400 {
		t.Fatal("status", response.StatusCode)
	}
	server.Close(ctx)
	mu.Lock()
	defer mu.Unlock()
	if strings.Contains(logs.String(), "superfluous") {
		t.Fatal(logs.String())
	}
}

func TestWebSocketOriginPolicy(t *testing.T) {
	ctx, n := newTestNetwork(t)
	server := must(t, n.ServeStream(ctx, "127.0.0.1:0", func(child *Execution, e HttpExchange) Result[Unit, HttpError] {
		allowed := NewList[string]()
		if e.Path(child) == "/listed" {
			allowed = NewList("https://app.example")
		}
		if r := e.Upgrade(child, allowed, NewList[string](), None[int]()); !r.Failed {
			r.Val.Close(child)
		}
		return Ok[Unit, HttpError](Unit{})
	}, serverOptions()))
	address := server.Address(ctx)
	dial := func(path, origin string) error {
		header := http.Header{}
		if origin != "" {
			header.Set("Origin", origin)
		}
		conn, resp, err := websocket.DefaultDialer.Dial("ws://"+address+path, header)
		if conn != nil {
			conn.Close()
		}
		if resp != nil {
			resp.Body.Close()
		}
		return err
	}
	if err := dial("/", ""); err != nil {
		t.Fatal("no Origin header:", err)
	}
	if err := dial("/", "http://"+address); err != nil {
		t.Fatal("same origin:", err)
	}
	if err := dial("/", "http://evil.example"); err == nil {
		t.Fatal("cross origin accepted without a list")
	}
	if err := dial("/listed", "https://app.example"); err != nil {
		t.Fatal("listed origin:", err)
	}
	if err := dial("/listed", "http://"+address); err == nil {
		t.Fatal("same origin accepted although a list was given")
	}
}

func TestWebSocketInvalidUTF8TextClosesWith1007(t *testing.T) {
	ctx, n := newTestNetwork(t)
	server := must(t, n.ServeStream(ctx, "127.0.0.1:0", func(child *Execution, e HttpExchange) Result[Unit, HttpError] {
		upgraded := e.Upgrade(child, NewList[string](), NewList[string](), Some(int(32)))
		if upgraded.Failed { // the test already finished and closed the network
			return Ok[Unit, HttpError](Unit{})
		}
		socket := upgraded.Val
		failedWith(t, socket.Receive(child), "WebSocketError_InvalidData")
		failedWith(t, socket.Receive(child), "WebSocketError_Closed")
		return Ok[Unit, HttpError](Unit{})
	}, serverOptions()))
	conn, _, err := websocket.DefaultDialer.Dial("ws://"+server.Address(ctx), nil)
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	if err := conn.WriteMessage(websocket.TextMessage, []byte{0xff, 0xfe}); err != nil {
		t.Fatal(err)
	}
	conn.SetReadDeadline(time.Now().Add(2 * time.Second))
	if _, _, err = conn.ReadMessage(); !websocket.IsCloseError(err, websocket.CloseInvalidFramePayloadData) {
		t.Fatal("expected close 1007, got", err)
	}
	server.Close(ctx)
}

func TestWebSocketServerShutdownJoinsSession(t *testing.T) {
	ctx, n := newTestNetwork(t)
	started := make(chan struct{})
	server := must(t, n.ServeStream(ctx, "127.0.0.1:0", func(child *Execution, e HttpExchange) Result[Unit, HttpError] {
		upgraded := e.Upgrade(child, NewList[string](), NewList[string](), Some(int(32)))
		if upgraded.Failed { // the test already finished and closed the network
			return Ok[Unit, HttpError](Unit{})
		}
		socket := upgraded.Val
		close(started)
		socket.Receive(child)
		return Ok[Unit, HttpError](Unit{})
	}, serverOptions()))
	socket := must(t, n.WebSocket(ctx, "ws://"+server.Address(ctx), headersOf(), NewList[string](), wsOptions(32, false)))
	<-started
	closed := make(chan struct{})
	go func() { server.Close(ctx); close(closed) }()
	select {
	case <-closed:
	case <-time.After(2 * time.Second):
		t.Fatal("WebSocket escaped server shutdown")
	}
	socket.Close(ctx)
}

func TestWebSocketCompressedMessageLimit(t *testing.T) {
	upgrader := websocket.Upgrader{EnableCompression: true}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		conn, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			return
		}
		defer conn.Close()
		conn.WriteMessage(websocket.TextMessage, []byte(strings.Repeat("x", 10000)))
	}))
	defer server.Close()
	ctx, n := newTestNetwork(t)
	socket := must(t, n.WebSocket(ctx, "ws"+strings.TrimPrefix(server.URL, "http"), headersOf(), NewList[string](), wsOptions(128, true)))
	failedWith(t, socket.Receive(ctx), "WebSocketError_LimitExceeded")
	failedWith(t, socket.Receive(ctx), "WebSocketError_Closed")
}

func TestWebSocketReceiveCancellationAndNetworkClose(t *testing.T) {
	ctx := testExec()
	n := NewOSNetwork()
	server := must(t, n.ServeStream(ctx, "127.0.0.1:0", func(child *Execution, e HttpExchange) Result[Unit, HttpError] {
		upgraded := e.Upgrade(child, NewList[string](), NewList[string](), None[int]())
		if upgraded.Failed { // the test already finished and closed the network
			return Ok[Unit, HttpError](Unit{})
		}
		socket := upgraded.Val
		socket.Receive(child)
		return Ok[Unit, HttpError](Unit{})
	}, serverOptions()))
	socket := must(t, n.WebSocket(ctx, "ws://"+server.Address(ctx), headersOf(), NewList[string](), wsOptions(32, false)))
	child, cancel := netCancelledExec(ctx)
	go func() { time.Sleep(20 * time.Millisecond); cancel() }()
	if !expectCancelled(func() { socket.Receive(child) }) {
		t.Fatal("receive did not unwind on cancellation")
	}
	// The interrupted session is failed, not reusable.
	failedWith(t, socket.Receive(ctx), "WebSocketError_Closed")
	n.Close(ctx)
	failedWith(t, socket.Send(ctx, NewBytes(nil), false), "WebSocketError_Closed")
}
