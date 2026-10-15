//go:build !ms_lean

package msruntime

import (
	"net"
	"net/http/httptest"
	"testing"
)

func TestAccessorResourceMetadataRemainsReadableAfterClose(t *testing.T) {
	ctx := RootExecution()
	metadata := Record{Type: "@std/HttpResponseMetadata", Fields: map[string]Value{"status": int64(200)}}
	body := &libraryResponseBody{metadata: metadata, closed: true}
	if ResponseBodyMetadataRead(ctx, body).(Record).Fields["status"] != int64(200) {
		t.Fatal("closed response metadata")
	}
	ResponseBodyMetadataRead(ctx, body).(Record).Fields["status"] = int64(201)
	if ResponseBodyMetadataRead(ctx, body).(Record).Fields["status"] != int64(201) {
		t.Fatal("response metadata copied")
	}
	request := httptest.NewRequest("CUSTOM", "http://example.test/a?b=c", nil)
	headers := &libraryHeaders{}
	exchange := &libraryHTTPExchange{request: request, headers: headers, closed: true}
	if HttpExchangeHeadersRead(ctx, exchange) != headers || HttpExchangePathRead(ctx, exchange) != "/a" || HttpExchangeQueryRead(ctx, exchange) != "b=c" || HttpMethodTextRead(ctx, HttpExchangeMethodRead(ctx, exchange)) != "CUSTOM" {
		t.Fatal("closed exchange metadata")
	}
	// net.Pipe keeps its endpoint addresses after close, like socket descriptors.
	left, right := net.Pipe()
	left.Close()
	right.Close()
	connection := &libraryConnection{conn: left, closed: true}
	if ConnectionLocalAddressRead(ctx, connection) != left.LocalAddr().String() || ConnectionPeerAddressRead(ctx, connection) != left.RemoteAddr().String() {
		t.Fatal("closed connection addresses")
	}
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	address := listener.Addr().String()
	listener.Close()
	if ListenerAddressRead(ctx, &libraryListener{listener: listener}) != address || HttpServerAddressRead(ctx, &httpService{listener: listener}) != address {
		t.Fatal("closed listener/server address")
	}
	datagram, err := net.ListenPacket("udp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	address = datagram.LocalAddr().String()
	datagram.Close()
	if DatagramSocketAddressRead(ctx, &libraryDatagram{conn: datagram, closed: true}) != address {
		t.Fatal("closed datagram address")
	}
}
