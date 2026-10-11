package msruntime

import (
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"github.com/gorilla/websocket"
	"io"
	"math/big"
	"net"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"runtime"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"golang.org/x/net/dns/dnsmessage"
)

func networkingTLSOptions() Record {
	return Record{"@std/TlsOptions", map[string]Value{"server_name": "", "roots_pem": "", "certificate_pem": "", "private_key_pem": "", "alpn": libraryStrings(nil), "require_client_certificate": false}}
}
func networkingClientOptions() Record {
	return Record{"@std/HttpClientOptions", map[string]Value{"max_redirects": int64(4), "max_idle_connections": int64(8), "max_header_bytes": int64(65536), "idle_timeout": Duration(time.Minute), "decompress": true, "cookies": true, "tls": networkingTLSOptions()}}
}
func networkingInvoke(ctx *Execution, v Value, name string, a ...Value) Value {
	return Bind(v, "", name).(Function).Body(ctx, a)
}
func TestNetworkingListenerReuseAfterCancellation(t *testing.T) {
	ctx := RootExecution()
	n := &network{}
	defer n.Operation("close").Body(ctx, nil)
	listener := librarySuccess(t, n.Operation("listen").Body(ctx, []Value{"127.0.0.1:0"}))
	libraryFailure(t, networkingInvoke(ctx, listener, "accept_timeout", Duration(time.Millisecond)), "Timeout")
	address := networkingInvoke(ctx, listener, "address").(string)
	client := librarySuccess(t, n.Operation("connect").Body(ctx, []Value{address, Duration(time.Second)}))
	accepted := librarySuccess(t, networkingInvoke(ctx, listener, "accept_timeout", Duration(time.Second)))
	librarySuccess(t, networkingInvoke(ctx, client, "write", Bytes{[]byte("x")}))
	value := librarySuccess(t, networkingInvoke(ctx, accepted, "read_timeout", int64(1), Duration(time.Second))).(Alternative)
	if value.Tag != "some" {
		t.Fatal(value)
	}
	libraryFailureIO(t, networkingInvoke(ctx, accepted, "read_timeout", int64(1), Duration(time.Millisecond)), "Failed")
}
func TestNetworkingPolicyAndUnix(t *testing.T) {
	ctx := RootExecution()
	n := &network{}
	defer n.Operation("close").Body(ctx, nil)
	restricted := librarySuccess(t, n.Operation("restrict").Body(ctx, []Value{libraryStrings([]string{"localhost"}), libraryStrings([]string{"127.0.0.0/8"}), true}))
	listener := librarySuccess(t, networkingInvoke(ctx, restricted, "listen", "127.0.0.1:0"))
	address := networkingInvoke(ctx, listener, "address").(string)
	librarySuccess(t, networkingInvoke(ctx, restricted, "connect", address, Duration(time.Second)))
	libraryFailure(t, networkingInvoke(ctx, restricted, "connect", "192.0.2.1:443", Duration(time.Second)), "PermissionDenied")
	libraryFailure(t, networkingInvoke(ctx, restricted, "lookup", "example.invalid", int64(10), Duration(time.Second)), "PermissionDenied")
	hostOnly := librarySuccess(t, n.Operation("restrict").Body(ctx, []Value{libraryStrings([]string{"localhost"}), libraryStrings(nil), false}))
	libraryFailure(t, networkingInvoke(ctx, hostOnly, "connect", address, Duration(time.Second)), "PermissionDenied")
	if runtime.GOOS == "windows" {
		return
	}
	path := filepath.Join(t.TempDir(), "socket")
	unix := librarySuccess(t, n.Operation("listen_unix").Body(ctx, []Value{path}))
	client := librarySuccess(t, n.Operation("connect_unix").Body(ctx, []Value{path, Duration(time.Second)}))
	server := librarySuccess(t, networkingInvoke(ctx, unix, "accept"))
	librarySuccess(t, networkingInvoke(ctx, client, "shutdown_write"))
	eof := librarySuccess(t, networkingInvoke(ctx, server, "read", int64(1))).(Alternative)
	if eof.Tag != "none" {
		t.Fatal(eof)
	}
}
func TestNetworkingDNSRecordsAndClose(t *testing.T) {
	socket, err := net.ListenPacket("udp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer socket.Close()
	done := make(chan struct{})
	defer close(done)
	go func() {
		buffer := make([]byte, 4096)
		for {
			n, peer, err := socket.ReadFrom(buffer)
			if err != nil {
				return
			}
			var parser dnsmessage.Parser
			header, err := parser.Start(buffer[:n])
			if err != nil {
				continue
			}
			question, err := parser.Question()
			if err != nil {
				continue
			}
			builder := dnsmessage.NewBuilder(nil, dnsmessage.Header{ID: header.ID, Response: true, RecursionAvailable: true})
			builder.StartQuestions()
			builder.Question(question)
			builder.StartAnswers()
			resource := dnsmessage.ResourceHeader{Name: question.Name, Type: question.Type, Class: dnsmessage.ClassINET, TTL: 30}
			switch question.Type {
			case dnsmessage.TypeA:
				builder.AResource(resource, dnsmessage.AResource{A: [4]byte{127, 0, 0, 1}})
			case dnsmessage.TypeAAAA:
				builder.AAAAResource(resource, dnsmessage.AAAAResource{AAAA: [16]byte{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1}})
			case dnsmessage.TypeTXT:
				builder.TXTResource(resource, dnsmessage.TXTResource{TXT: []string{"hello"}})
			case dnsmessage.TypeMX:
				builder.MXResource(resource, dnsmessage.MXResource{Pref: 10, MX: dnsmessage.MustNewName("mail.test.")})
			case dnsmessage.TypeNS:
				builder.NSResource(resource, dnsmessage.NSResource{NS: dnsmessage.MustNewName("ns.test.")})
			case dnsmessage.TypeCNAME:
				builder.CNAMEResource(resource, dnsmessage.CNAMEResource{CNAME: dnsmessage.MustNewName("alias.test.")})
			case dnsmessage.TypePTR:
				builder.PTRResource(resource, dnsmessage.PTRResource{PTR: dnsmessage.MustNewName("host.test.")})
			case dnsmessage.TypeSRV:
				builder.SRVResource(resource, dnsmessage.SRVResource{Priority: 1, Weight: 2, Port: 443, Target: dnsmessage.MustNewName("service.test.")})
			}
			data, err := builder.Finish()
			if err == nil {
				socket.WriteTo(data, peer)
			}
		}
	}()
	ctx := RootExecution()
	n := &network{}
	defer n.Operation("close").Body(ctx, nil)
	resolver := librarySuccess(t, n.Operation("with_resolver").Body(ctx, []Value{socket.LocalAddr().String()}))
	for _, kind := range []string{"A", "AAAA", "TXT", "MX", "NS", "PTR", "SRV"} {
		name := "test."
		if kind == "PTR" {
			name = "127.0.0.1"
		}
		records := librarySuccess(t, networkingInvoke(ctx, resolver, "resolve", name, kind, int64(8), Duration(time.Second))).(List)
		if len(records.Items) == 0 {
			t.Fatal(kind, "no records")
		}
	}
	blocking := &network{resolver: &net.Resolver{PreferGo: true, Dial: func(ctx context.Context, _, _ string) (net.Conn, error) { <-ctx.Done(); return nil, ctx.Err() }}}
	finished := make(chan Value, 1)
	go func() { finished <- blocking.Operation("connect").Body(ctx, []Value{"test:80", Duration(time.Minute)}) }()
	for i := 0; i < 100; i++ {
		blocking.mu.Lock()
		started := len(blocking.calls) > 0
		blocking.mu.Unlock()
		if started {
			break
		}
		time.Sleep(time.Millisecond)
	}
	blocking.Operation("close").Body(ctx, nil)
	select {
	case v := <-finished:
		libraryFailure(t, v, "Closed")
	case <-time.After(time.Second):
		t.Fatal("unjoined acquisition")
	}
}
func TestNetworkingClientPoolingCookiesStreaming(t *testing.T) {
	var requests atomic.Int64
	var connections atomic.Int64
	server := httptest.NewUnstartedServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requests.Add(1)
		switch r.URL.Path {
		case "/redirect":
			http.SetCookie(w, &http.Cookie{Name: "session", Value: "yes", Path: "/"})
			http.Redirect(w, r, "/cookie", 302)
		case "/cookie":
			if cookie, err := r.Cookie("session"); err != nil || cookie.Value != "yes" {
				http.Error(w, "missing cookie", 500)
				return
			}
			w.Header().Add("X-Multi", "a")
			w.Header().Add("X-Multi", "b")
			io.WriteString(w, "streamed")
		default:
			io.Copy(w, r.Body)
		}
	}))
	server.Config.ConnState = func(_ net.Conn, s http.ConnState) {
		if s == http.StateNew {
			connections.Add(1)
		}
	}
	server.Start()
	defer server.Close()
	ctx := RootExecution()
	n := &network{}
	defer n.Operation("close").Body(ctx, nil)
	client := librarySuccess(t, n.Operation("http_client").Body(ctx, []Value{networkingClientOptions()}))
	headers := Map{"@std/Map[String][String]", nil}
	for i := 0; i < 2; i++ {
		body := librarySuccess(t, networkingInvoke(ctx, client, "send", "GET", server.URL+"/redirect", headers, Bytes{}, int64(100), Duration(time.Second)))
		var text strings.Builder
		for {
			part := librarySuccess(t, networkingInvoke(ctx, body, "read", int64(3))).(Alternative)
			if part.Tag == "none" {
				break
			}
			text.Write(part.Fields[0].(Bytes).Items)
		}
		if text.String() != "streamed" {
			t.Fatal(text.String())
		}
		networkingInvoke(ctx, body, "close")
	}
	if connections.Load() != 1 {
		t.Fatal("did not reuse connection", connections.Load())
	}
	if requests.Load() != 4 {
		t.Fatal(requests.Load())
	}
}
func TestNetworkingTLSVerificationAndHTTP2(t *testing.T) {
	server := httptest.NewUnstartedServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { io.WriteString(w, r.Proto) }))
	server.EnableHTTP2 = true
	server.StartTLS()
	defer server.Close()
	cert := server.Certificate()
	roots := string(pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: cert.Raw}))
	ctx := RootExecution()
	n := &network{}
	defer n.Operation("close").Body(ctx, nil)
	options := networkingClientOptions()
	tlsOptions := networkingTLSOptions()
	tlsOptions.Fields["roots_pem"] = roots
	options.Fields["tls"] = tlsOptions
	client := librarySuccess(t, n.Operation("http_client").Body(ctx, []Value{options}))
	response := librarySuccess(t, networkingInvoke(ctx, client, "send", "GET", server.URL, Map{"@std/Map[String][String]", nil}, Bytes{}, int64(100), Duration(time.Second)))
	part := librarySuccess(t, networkingInvoke(ctx, response, "read", int64(100))).(Alternative)
	if string(part.Fields[0].(Bytes).Items) != "HTTP/2.0" {
		t.Fatal(part)
	}
	networkingInvoke(ctx, response, "close")
	librarySuccess(t, libraryCall(t, "tls/verify_certificates", roots, roots, "example.com", libraryTimestamp{time.Now()}))
	libraryFailure(t, libraryCall(t, "tls/verify_certificates", roots, roots, "wrong.invalid", libraryTimestamp{time.Now()}), "AuthenticationFailed")
	pool := x509.NewCertPool()
	pool.AddCert(cert)
	rawTLS := tlsOptions
	rawTLS.Fields["server_name"] = "example.com"
	conn := librarySuccess(t, n.Operation("connect_tls_config").Body(ctx, []Value{server.Listener.Addr().String(), rawTLS, Duration(time.Second)}))
	info := librarySuccess(t, networkingInvoke(ctx, conn, "tls_info")).(Record)
	if info.Fields["verified"] != true {
		t.Fatal(info)
	}
}

func networkingServerOptions() Record {
	return Record{"@std/HttpServerOptions", map[string]Value{"max_requests": int64(8), "max_body_bytes": int64(1 << 20), "max_response_bytes": int64(1 << 20), "max_header_bytes": int64(65536), "timeout": Duration(3 * time.Second), "grace": Duration(10 * time.Millisecond), "tls": Alternative{"@std/Optional[@std/TlsOptions]", "none", nil}}}
}
func TestNetworkingStreamingServerAndWebSocket(t *testing.T) {
	ctx := RootExecution()
	n := &network{}
	defer n.Operation("close").Body(ctx, nil)
	handler := NewFunction([]string{"exchange"}, "@std/Result[Unit][@std/LibraryError]", func(child *Execution, a []Value) Value {
		exchange := a[0]
		if networkingInvoke(child, exchange, "path") == "/ws" {
			socket := librarySuccess(t, networkingInvoke(child, exchange, "upgrade", libraryStrings(nil), libraryStrings([]string{"echo"}), int64(32)))
			message := librarySuccess(t, networkingInvoke(child, socket, "receive")).(Alternative)
			if message.Tag == "some" {
				fields := message.Fields[0].(Record).Fields
				librarySuccess(t, networkingInvoke(child, socket, "send", fields["data"], fields["text"]))
			}
			return libraryOK("@std/Result[Unit][@std/LibraryError]", Unit{})
		}
		librarySuccess(t, networkingInvoke(child, exchange, "send_headers", int64(200), Map{"@std/Map[String][@std/List[String]]", nil}))
		for {
			part := librarySuccess(t, networkingInvoke(child, exchange, "read", int64(3))).(Alternative)
			if part.Tag == "none" {
				break
			}
			librarySuccess(t, networkingInvoke(child, exchange, "write", part.Fields[0]))
		}
		return libraryOK("@std/Result[Unit][@std/LibraryError]", Unit{})
	})
	server := librarySuccess(t, n.Operation("serve_stream").Body(ctx, []Value{"127.0.0.1:0", handler, networkingServerOptions()}))
	address := networkingInvoke(ctx, server, "address").(string)
	client := librarySuccess(t, n.Operation("http_client").Body(ctx, []Value{networkingClientOptions()}))
	input := &networkingReadStream{data: []byte("bounded streaming upload")}
	body := librarySuccess(t, networkingInvoke(ctx, client, "send_stream", "POST", "http://"+address, Map{"@std/Map[String][String]", nil}, ViewOf("@std/ReadStream&Shareable", input), int64(1000), Duration(time.Second)))
	var out strings.Builder
	for {
		part := librarySuccess(t, networkingInvoke(ctx, body, "read", int64(4))).(Alternative)
		if part.Tag == "none" {
			break
		}
		out.Write(part.Fields[0].(Bytes).Items)
	}
	networkingInvoke(ctx, body, "close")
	if out.String() != "bounded streaming upload" || input.closed {
		t.Fatal(out.String(), "borrowed input closed:", input.closed)
	}
	options := Record{"@std/WebSocketOptions", map[string]Value{"max_message_bytes": int64(32), "timeout": Duration(time.Second), "tls": networkingTLSOptions(), "compression": false}}
	socket := librarySuccess(t, n.Operation("web_socket").Body(ctx, []Value{"ws://" + address + "/ws", Map{"@std/Map[String][String]", nil}, libraryStrings([]string{"echo"}), options}))
	if networkingInvoke(ctx, socket, "subprotocol") != "echo" {
		t.Fatal("subprotocol")
	}
	librarySuccess(t, networkingInvoke(ctx, socket, "send", Bytes{[]byte("hello")}, true))
	message := librarySuccess(t, networkingInvoke(ctx, socket, "receive")).(Alternative)
	if message.Tag != "some" || string(message.Fields[0].(Record).Fields["data"].(Bytes).Items) != "hello" {
		t.Fatal(message)
	}
	networkingInvoke(ctx, socket, "close")
	networkingInvoke(ctx, server, "close")
}

type networkingReadStream struct {
	data   []byte
	closed bool
}

func (s *networkingReadStream) Operation(name string) Function {
	if name == "close" {
		return NewFunction(nil, "Unit", func(_ *Execution, _ []Value) Value { s.closed = true; return Unit{} })
	}
	return NewFunction([]string{"max_bytes"}, "@std/Result[@std/Optional[@std/Bytes]][@std/IoError]", func(_ *Execution, a []Value) Value {
		if len(s.data) == 0 {
			return libraryOK("@std/Result[@std/Optional[@std/Bytes]][@std/IoError]", optional("@std/Bytes", nil, false))
		}
		max := int(a[0].(int64))
		if max > len(s.data) {
			max = len(s.data)
		}
		part := append([]byte{}, s.data[:max]...)
		s.data = s.data[max:]
		return libraryOK("@std/Result[@std/Optional[@std/Bytes]][@std/IoError]", optional("@std/Bytes", Bytes{part}, true))
	})
}
func TestNetworkingServerShutdownJoinsWebSocket(t *testing.T) {
	ctx := RootExecution()
	n := &network{}
	defer n.Operation("close").Body(ctx, nil)
	started := make(chan struct{})
	handler := NewFunction([]string{"exchange"}, "@std/Result[Unit][@std/LibraryError]", func(child *Execution, a []Value) Value {
		socket := librarySuccess(t, networkingInvoke(child, a[0], "upgrade", libraryStrings(nil), libraryStrings(nil), int64(32)))
		close(started)
		networkingInvoke(child, socket, "receive")
		return libraryOK("@std/Result[Unit][@std/LibraryError]", Unit{})
	})
	server := librarySuccess(t, n.Operation("serve_stream").Body(ctx, []Value{"127.0.0.1:0", handler, networkingServerOptions()}))
	address := networkingInvoke(ctx, server, "address").(string)
	options := Record{"@std/WebSocketOptions", map[string]Value{"max_message_bytes": int64(32), "timeout": Duration(time.Second), "tls": networkingTLSOptions(), "compression": false}}
	socket := librarySuccess(t, n.Operation("web_socket").Body(ctx, []Value{"ws://" + address, Map{"@std/Map[String][String]", nil}, libraryStrings(nil), options}))
	<-started
	closed := make(chan struct{})
	go func() { networkingInvoke(ctx, server, "close"); close(closed) }()
	select {
	case <-closed:
	case <-time.After(time.Second):
		t.Fatal("WebSocket escaped server shutdown")
	}
	networkingInvoke(ctx, socket, "close")
}

func TestNetworkingMutualTLSListener(t *testing.T) {
	keyPub, key, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	now := time.Now()
	rootTemplate := &x509.Certificate{SerialNumber: big.NewInt(1), Subject: pkix.Name{CommonName: "test CA"}, NotBefore: now.Add(-time.Minute), NotAfter: now.Add(time.Hour), IsCA: true, BasicConstraintsValid: true, KeyUsage: x509.KeyUsageCertSign}
	rootDER, err := x509.CreateCertificate(rand.Reader, rootTemplate, rootTemplate, keyPub, key)
	if err != nil {
		t.Fatal(err)
	}
	root, err := x509.ParseCertificate(rootDER)
	if err != nil {
		t.Fatal(err)
	}
	issue := func(serial int64, name string, usage x509.ExtKeyUsage) (string, string) {
		pub, private, err := ed25519.GenerateKey(rand.Reader)
		if err != nil {
			t.Fatal(err)
		}
		template := &x509.Certificate{SerialNumber: big.NewInt(serial), Subject: pkix.Name{CommonName: name}, DNSNames: []string{name}, NotBefore: now.Add(-time.Minute), NotAfter: now.Add(time.Hour), ExtKeyUsage: []x509.ExtKeyUsage{usage}, KeyUsage: x509.KeyUsageDigitalSignature}
		der, err := x509.CreateCertificate(rand.Reader, template, root, pub, key)
		if err != nil {
			t.Fatal(err)
		}
		pk, err := x509.MarshalPKCS8PrivateKey(private)
		if err != nil {
			t.Fatal(err)
		}
		return string(pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der})), string(pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: pk}))
	}
	cert, keyPEM := issue(2, "service.test", x509.ExtKeyUsageServerAuth)
	clientCert, clientKey := issue(3, "client.test", x509.ExtKeyUsageClientAuth)
	roots := string(pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: rootDER}))
	ctx := RootExecution()
	n := &network{}
	defer n.Operation("close").Body(ctx, nil)
	serverOptions := networkingTLSOptions()
	serverOptions.Fields["certificate_pem"] = cert
	serverOptions.Fields["private_key_pem"] = keyPEM
	serverOptions.Fields["roots_pem"] = roots
	serverOptions.Fields["require_client_certificate"] = true
	listener := librarySuccess(t, n.Operation("listen_tls").Body(ctx, []Value{"127.0.0.1:0", serverOptions, Duration(time.Second)}))
	address := networkingInvoke(ctx, listener, "address").(string)
	accepted := make(chan Value, 1)
	go func() { accepted <- networkingInvoke(ctx, listener, "accept_timeout", Duration(time.Second)) }()
	clientOptions := networkingTLSOptions()
	clientOptions.Fields["server_name"] = "service.test"
	clientOptions.Fields["roots_pem"] = roots
	clientOptions.Fields["certificate_pem"] = clientCert
	clientOptions.Fields["private_key_pem"] = clientKey
	client := librarySuccess(t, n.Operation("connect_tls_config").Body(ctx, []Value{address, clientOptions, Duration(time.Second)}))
	server := librarySuccess(t, <-accepted)
	librarySuccess(t, networkingInvoke(ctx, client, "write", Bytes{[]byte("verified")}))
	message := librarySuccess(t, networkingInvoke(ctx, server, "read_timeout", int64(20), Duration(time.Second))).(Alternative)
	if string(message.Fields[0].(Bytes).Items) != "verified" {
		t.Fatal(message)
	}
}
func TestNetworkingCompressedWebSocketLimit(t *testing.T) {
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
	ctx := RootExecution()
	n := &network{}
	defer n.Operation("close").Body(ctx, nil)
	options := Record{"@std/WebSocketOptions", map[string]Value{"max_message_bytes": int64(128), "timeout": Duration(time.Second), "tls": networkingTLSOptions(), "compression": true}}
	socket := librarySuccess(t, n.Operation("web_socket").Body(ctx, []Value{"ws" + strings.TrimPrefix(server.URL, "http"), Map{"@std/Map[String][String]", nil}, libraryStrings(nil), options}))
	libraryFailure(t, networkingInvoke(ctx, socket, "receive"), "LimitExceeded")
	libraryFailure(t, networkingInvoke(ctx, socket, "receive"), "Closed")
}
