package msruntime

import (
	"context"
	"net"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"golang.org/x/net/dns/dnsmessage"
)

func TestIpAddressPolicy(t *testing.T) {
	ctx := testExec()
	for _, tc := range []struct{ input, text, family string }{
		{"192.0.2.1", "192.0.2.1", "IPv4"},
		{"2001:0db8::1", "2001:db8::1", "IPv6"},
		{"::ffff:192.0.2.1", "192.0.2.1", "IPv4"},
	} {
		address := must(t, Net_ParseIp(ctx, tc.input))
		if got := IpAddress_Text(ctx, address); got != tc.text {
			t.Fatal(got, tc)
		}
		if got := IpFamily_Text(ctx, IpAddress_Family(ctx, address)); got != tc.family {
			t.Fatal(got, tc)
		}
	}
	for _, input := range []string{"", "999.1.1.1", "192.168.001.1", "fe80::1%eth0", "[::1]"} {
		failedWith(t, Net_ParseIp(ctx, input), "NetworkError_InvalidData")
	}
}

func TestCidrContainsAndCanonicalText(t *testing.T) {
	ctx := testExec()
	cidr := must(t, Net_ParseCidr(ctx, "192.0.2.77/24"))
	if got := Cidr_Text(ctx, cidr); got != "192.0.2.0/24" {
		t.Fatal("host bits kept:", got)
	}
	in := must(t, Net_ParseIp(ctx, "192.0.2.200"))
	out := must(t, Net_ParseIp(ctx, "192.0.3.1"))
	if !must(t, Net_ContainsIp(ctx, cidr, in)) || must(t, Net_ContainsIp(ctx, cidr, out)) {
		t.Fatal("membership")
	}
	// Mapped IPv6 input is normalized to IPv4 before testing membership.
	mapped := must(t, Net_ParseIp(ctx, "::ffff:192.0.2.9"))
	if !must(t, Net_ContainsIp(ctx, cidr, mapped)) {
		t.Fatal("mapped address not normalized")
	}
	for _, bad := range []string{"", "192.0.2.0", "192.0.2.0/33", "::1/129", "x/8"} {
		failedWith(t, Net_ParseCidr(ctx, bad), "NetworkError_InvalidData")
	}
}

func TestDnsKindAndFamilyText(t *testing.T) {
	ctx := testExec()
	kinds := map[string]DnsKind{"A": DnsKind_A{}, "AAAA": DnsKind_AAAA{}, "CNAME": DnsKind_CNAME{}, "MX": DnsKind_MX{}, "NS": DnsKind_NS{}, "TXT": DnsKind_TXT{}, "PTR": DnsKind_PTR{}, "SRV": DnsKind_SRV{}}
	for want, kind := range kinds {
		if got := DnsKind_Text(ctx, kind); got != want {
			t.Fatal(got, want)
		}
	}
}

func TestNetworkErrorMessagesRedact(t *testing.T) {
	ctx := testExec()
	for err, want := range map[NetworkError]string{
		NetworkError_InvalidInput{}:     "network: invalid input",
		NetworkError_InvalidData{}:      "network: invalid data",
		NetworkError_LimitExceeded{}:    "network: limit exceeded",
		NetworkError_PermissionDenied{}: "network: permission denied",
		NetworkError_Unsupported{}:      "network: operation not supported",
		NetworkError_Closed{}:           "network: resource is closed",
		NetworkError_Timeout{}:          "network: operation timed out",
	} {
		if got := Errors_Message_NetworkError(ctx, err); got != want {
			t.Errorf("%T: %q, want %q", err, got, want)
		}
	}
	if got := Errors_Message_NetworkError(ctx, NetworkError_Failed{Message: "dial 192.0.2.1:9: refused"}); got != "dial 192.0.2.1:9: refused" {
		t.Fatal("Failed text must be verbatim:", got)
	}
	// A refused connection reports the host's text; no secret from the call
	// arguments is added beyond what the host error itself names.
	_, n := newTestNetwork(t)
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	address := listener.Addr().String()
	listener.Close()
	e := failedWith(t, n.Connect(ctx, address, Some(Duration(time.Second))), "NetworkError_Failed")
	if message := Errors_Message_NetworkError(ctx, e); !strings.Contains(message, "refused") {
		t.Fatal(message)
	}
}

func TestNetNetworkIsStableRoot(t *testing.T) {
	ctx := testExec()
	first := Net_Network(ctx)
	if first == nil || Net_Network(ctx) != first {
		t.Fatal("root changed between calls")
	}
	wired := NewOSNetwork()
	ctx2 := testExec()
	ctx2.State.Host.Network = wired
	if Net_Network(ctx2) != wired {
		t.Fatal("host-wired network not used")
	}
	first.Close(ctx)
}

func TestListenerReuseAfterTimeout(t *testing.T) {
	ctx, n := newTestNetwork(t)
	listener := must(t, n.Listen(ctx, "127.0.0.1:0"))
	failedWith(t, listener.Accept(ctx, Some(Duration(time.Millisecond))), "NetworkError_Timeout")
	address := listener.Address(ctx)
	client := must(t, n.Connect(ctx, address, Some(Duration(time.Second))))
	accepted := must(t, listener.Accept(ctx, Some(Duration(time.Second))))
	must(t, client.WriteBytes(ctx, NewBytes([]byte("x")), None[Duration]()))
	if got := someBytes(t, accepted.Read(ctx, Some(int(1)), Some(Duration(time.Second)))); got != "x" {
		t.Fatal(got)
	}
	// A local read timeout is IoError.Failed, never NetworkError.Timeout.
	failedWith(t, accepted.Read(ctx, Some(int(1)), Some(Duration(time.Millisecond))), "IoError_Failed")
	if client.PeerAddress(ctx) != address || client.LocalAddress(ctx) != accepted.PeerAddress(ctx) {
		t.Fatal("addresses")
	}
}

func TestNegativeLimitsAreInvalidInput(t *testing.T) {
	ctx, n := newTestNetwork(t)
	neg := Some(Duration(-1))
	failedWith(t, n.Connect(ctx, "127.0.0.1:1", neg), "NetworkError_InvalidInput")
	failedWith(t, n.ConnectTls(ctx, "127.0.0.1:1", "", None[Duration]()), "NetworkError_InvalidInput")
	failedWith(t, n.Lookup(ctx, "localhost", Some(int(-1)), None[Duration]()), "NetworkError_InvalidInput")
	failedWith(t, n.Resolve(ctx, "localhost", DnsKind_A{}, None[int](), neg), "NetworkError_InvalidInput")
	listener := must(t, n.Listen(ctx, "127.0.0.1:0"))
	failedWith(t, listener.Accept(ctx, neg), "NetworkError_InvalidInput")
	conn := must(t, n.Connect(ctx, listener.Address(ctx), None[Duration]()))
	failedWith(t, conn.Read(ctx, Some(int(0)), None[Duration]()), "IoError_InvalidInput")
	failedWith(t, conn.Read(ctx, Some(int(-1)), None[Duration]()), "IoError_InvalidInput")
	failedWith(t, conn.WriteBytes(ctx, NewBytes(nil), neg), "IoError_InvalidInput")
	socket := must(t, n.BindDatagram(ctx, "127.0.0.1:0"))
	failedWith(t, socket.Receive(ctx, Some(int(0)), None[Duration]()), "NetworkError_InvalidInput")
	failedWith(t, socket.Receive(ctx, Some(int(65536)), None[Duration]()), "NetworkError_InvalidInput")
	failedWith(t, n.Listen(ctx, "not-an-address"), "NetworkError_Failed")
}

func TestConnectionCloseIsIdempotentAndReportsClosed(t *testing.T) {
	ctx, n := newTestNetwork(t)
	listener := must(t, n.Listen(ctx, "127.0.0.1:0"))
	client := must(t, n.Connect(ctx, listener.Address(ctx), None[Duration]()))
	server := must(t, listener.Accept(ctx, Some(Duration(time.Second))))
	local, peer := client.LocalAddress(ctx), client.PeerAddress(ctx)
	var wg sync.WaitGroup
	for range 4 {
		wg.Add(1)
		go func() { defer wg.Done(); client.Close(ctx) }()
	}
	wg.Wait()
	client.Close(ctx)
	failedWith(t, client.Read(ctx, Some(int(1)), None[Duration]()), "IoError_Closed")
	failedWith(t, client.WriteBytes(ctx, NewBytes([]byte("x")), None[Duration]()), "IoError_Closed")
	failedWith(t, client.ShutdownWrite(ctx), "NetworkError_Closed")
	// Metadata remains readable after close.
	if client.LocalAddress(ctx) != local || client.PeerAddress(ctx) != peer {
		t.Fatal("addresses changed after close")
	}
	// The peer sees end of stream.
	if o := must(t, server.Read(ctx, Some(int(1)), Some(Duration(time.Second)))); o.Some {
		t.Fatal("expected EOF")
	}
	listener.Close(ctx)
	listener.Close(ctx)
	failedWith(t, listener.Accept(ctx, None[Duration]()), "NetworkError_Closed")
	if listener.Address(ctx) == "" {
		t.Fatal("address after close")
	}
}

func TestCloseInterruptsBlockedRead(t *testing.T) {
	ctx, n := newTestNetwork(t)
	listener := must(t, n.Listen(ctx, "127.0.0.1:0"))
	client := must(t, n.Connect(ctx, listener.Address(ctx), None[Duration]()))
	must(t, listener.Accept(ctx, Some(Duration(time.Second))))
	done := make(chan Result[Option[*Bytes], IoError], 1)
	go func() { done <- client.Read(ctx, Some(int(1)), None[Duration]()) }()
	time.Sleep(20 * time.Millisecond)
	client.Close(ctx)
	select {
	case r := <-done:
		failedWith(t, r, "IoError_Closed")
	case <-time.After(2 * time.Second):
		t.Fatal("close did not interrupt the read")
	}
}

func TestCancellationUnwindsBlockedCalls(t *testing.T) {
	ctx, n := newTestNetwork(t)
	listener := must(t, n.Listen(ctx, "127.0.0.1:0"))
	child, cancel := netCancelledExec(ctx)
	go func() { time.Sleep(20 * time.Millisecond); cancel() }()
	if !expectCancelled(func() { listener.Accept(child, None[Duration]()) }) {
		t.Fatal("accept did not unwind on cancellation")
	}
	// The listener survives a cancelled accept.
	failedWith(t, listener.Accept(ctx, Some(Duration(time.Millisecond))), "NetworkError_Timeout")
	client := must(t, n.Connect(ctx, listener.Address(ctx), None[Duration]()))
	must(t, listener.Accept(ctx, Some(Duration(time.Second))))
	child, cancel = netCancelledExec(ctx)
	go func() { time.Sleep(20 * time.Millisecond); cancel() }()
	if !expectCancelled(func() { client.Read(child, Some(int(1)), None[Duration]()) }) {
		t.Fatal("read did not unwind on cancellation")
	}
}

func TestUnixSocketsAndHalfClose(t *testing.T) {
	ctx, n := newTestNetwork(t)
	path := filepath.Join(t.TempDir(), "socket")
	unix := must(t, n.ListenUnix(ctx, path))
	client := must(t, n.ConnectUnix(ctx, path, Some(Duration(time.Second))))
	server := must(t, unix.Accept(ctx, Some(Duration(time.Second))))
	must(t, client.ShutdownWrite(ctx))
	if o := must(t, server.Read(ctx, Some(int(1)), Some(Duration(time.Second)))); o.Some {
		t.Fatal("expected EOF after half close")
	}
	// The closing side can still read.
	must(t, server.WriteBytes(ctx, NewBytes([]byte("reply")), None[Duration]()))
	if got := someBytes(t, client.Read(ctx, Some(int(10)), Some(Duration(time.Second)))); got != "reply" {
		t.Fatal(got)
	}
}

func TestRestrictedNetworkPolicy(t *testing.T) {
	ctx, n := newTestNetwork(t)
	restricted := must(t, n.Restrict(ctx, NewList("localhost"), NewList("127.0.0.0/8"), true))
	listener := must(t, restricted.Listen(ctx, "127.0.0.1:0"))
	address := listener.Address(ctx)
	must(t, restricted.Connect(ctx, address, Some(Duration(time.Second))))
	failedWith(t, restricted.Connect(ctx, "192.0.2.1:443", Some(Duration(time.Second))), "NetworkError_PermissionDenied")
	failedWith(t, restricted.Lookup(ctx, "example.invalid", Some(int(10)), Some(Duration(time.Second))), "NetworkError_PermissionDenied")
	failedWith(t, restricted.Listen(ctx, "192.0.2.1:0"), "NetworkError_PermissionDenied")
	failedWith(t, restricted.ListenUnix(ctx, filepath.Join(t.TempDir(), "s")), "NetworkError_PermissionDenied")
	failedWith(t, restricted.ConnectUnix(ctx, filepath.Join(t.TempDir(), "s"), None[Duration]()), "NetworkError_PermissionDenied")
	hostOnly := must(t, n.Restrict(ctx, NewList("localhost"), NewList[string](), false))
	failedWith(t, hostOnly.Connect(ctx, address, Some(Duration(time.Second))), "NetworkError_PermissionDenied")
	failedWith(t, hostOnly.Listen(ctx, "127.0.0.1:0"), "NetworkError_PermissionDenied")
	// A child can only narrow its parent.
	narrow := must(t, restricted.Restrict(ctx, NewList("localhost"), NewList("10.0.0.0/8"), true))
	failedWith(t, narrow.Connect(ctx, address, Some(Duration(time.Second))), "NetworkError_PermissionDenied")
	failedWith(t, n.Restrict(ctx, NewList("bad host"), NewList[string](), false), "NetworkError_InvalidInput")
	failedWith(t, n.Restrict(ctx, NewList[string](), NewList("not-a-cidr"), false), "NetworkError_InvalidInput")
	// A restricted network cannot widen by resolving with an unlisted server.
	failedWith(t, restricted.WithResolver(ctx, "192.0.2.53:53"), "NetworkError_PermissionDenied")
	failedWith(t, n.WithResolver(ctx, "resolver.example:53"), "NetworkError_InvalidInput")
}

func TestNetworkCloseClosesDerivedAndOwnedResources(t *testing.T) {
	ctx := testExec()
	n := NewOSNetwork()
	child := must(t, n.Restrict(ctx, NewList("localhost"), NewList("127.0.0.0/8"), true))
	listener := must(t, child.Listen(ctx, "127.0.0.1:0"))
	address := listener.Address(ctx)
	conn := must(t, child.Connect(ctx, address, Some(Duration(time.Second))))
	socket := must(t, n.BindDatagram(ctx, "127.0.0.1:0"))
	n.Close(ctx)
	n.Close(ctx)
	failedWith(t, conn.Read(ctx, Some(int(1)), None[Duration]()), "IoError_Closed")
	failedWith(t, listener.Accept(ctx, None[Duration]()), "NetworkError_Closed")
	failedWith(t, socket.Receive(ctx, None[int](), None[Duration]()), "NetworkError_Closed")
	failedWith(t, child.Connect(ctx, address, None[Duration]()), "NetworkError_Closed")
	failedWith(t, n.Listen(ctx, "127.0.0.1:0"), "NetworkError_Closed")
	failedWith(t, n.Lookup(ctx, "localhost", None[int](), None[Duration]()), "NetworkError_Closed")
	failedWith(t, n.Restrict(ctx, NewList("a"), NewList[string](), false), "NetworkError_Closed")
}

func TestNetworkCloseJoinsInFlightDial(t *testing.T) {
	ctx := testExec()
	blocking := &osNetwork{resolver: &net.Resolver{PreferGo: true, Dial: func(ctx context.Context, _, _ string) (net.Conn, error) { <-ctx.Done(); return nil, ctx.Err() }}}
	finished := make(chan Result[Connection, NetworkError], 1)
	go func() { finished <- blocking.Connect(ctx, "test:80", Some(Duration(time.Minute))) }()
	for range 200 {
		blocking.mu.Lock()
		started := len(blocking.calls) > 0
		blocking.mu.Unlock()
		if started {
			break
		}
		time.Sleep(time.Millisecond)
	}
	blocking.Close(ctx)
	select {
	case r := <-finished:
		failedWith(t, r, "NetworkError_Closed")
	case <-time.After(time.Second):
		t.Fatal("close did not cancel and join the dial")
	}
}

func TestDatagramSockets(t *testing.T) {
	ctx, n := newTestNetwork(t)
	a := must(t, n.BindDatagram(ctx, "127.0.0.1:0"))
	b := must(t, n.BindDatagram(ctx, "127.0.0.1:0"))
	must(t, a.SendBytes(ctx, NewBytes([]byte("hello")), b.Address(ctx), None[Duration]()))
	d := must(t, b.Receive(ctx, None[int](), Some(Duration(time.Second))))
	if str(d.Data) != "hello" || d.Sender != a.Address(ctx) {
		t.Fatal(str(d.Data), d.Sender)
	}
	// Message boundaries include empty messages.
	must(t, a.SendBytes(ctx, NewBytes(nil), b.Address(ctx), None[Duration]()))
	if d := must(t, b.Receive(ctx, None[int](), Some(Duration(time.Second)))); len(d.Data.Data) != 0 {
		t.Fatal("empty datagram")
	}
	// An oversized datagram is discarded with LimitExceeded, never truncated.
	must(t, a.SendBytes(ctx, NewBytes([]byte("0123456789")), b.Address(ctx), None[Duration]()))
	failedWith(t, b.Receive(ctx, Some(int(4)), Some(Duration(time.Second))), "NetworkError_LimitExceeded")
	failedWith(t, b.Receive(ctx, None[int](), Some(Duration(10*time.Millisecond))), "NetworkError_Timeout")
	b.Close(ctx)
	b.Close(ctx)
	failedWith(t, b.Receive(ctx, None[int](), None[Duration]()), "NetworkError_Closed")
	failedWith(t, b.SendBytes(ctx, NewBytes(nil), a.Address(ctx), None[Duration]()), "NetworkError_Closed")
	if b.Address(ctx) == "" {
		t.Fatal("address after close")
	}
	restricted := must(t, n.Restrict(ctx, NewList("localhost"), NewList("127.0.0.0/8"), true))
	r := must(t, restricted.BindDatagram(ctx, "127.0.0.1:0"))
	failedWith(t, r.SendBytes(ctx, NewBytes(nil), "192.0.2.1:9", None[Duration]()), "NetworkError_PermissionDenied")
	failedWith(t, restricted.BindDatagram(ctx, "192.0.2.1:0"), "NetworkError_PermissionDenied")
}

// fakeDNS answers every query type with fixed records.
func fakeDNS(t *testing.T) string {
	socket, err := net.ListenPacket("udp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { socket.Close() })
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
				builder.AAAAResource(resource, dnsmessage.AAAAResource{AAAA: [16]byte{15: 1}})
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
			if data, err := builder.Finish(); err == nil {
				socket.WriteTo(data, peer)
			}
		}
	}()
	return socket.LocalAddr().String()
}

func TestDnsRecordsThroughExplicitResolver(t *testing.T) {
	ctx, n := newTestNetwork(t)
	resolver := must(t, n.WithResolver(ctx, fakeDNS(t)))
	for _, kind := range []DnsKind{DnsKind_A{}, DnsKind_AAAA{}, DnsKind_CNAME{}, DnsKind_TXT{}, DnsKind_MX{}, DnsKind_NS{}, DnsKind_PTR{}, DnsKind_SRV{}} {
		name := "test."
		if _, ptr := kind.(DnsKind_PTR); ptr {
			name = "127.0.0.1"
		}
		records := must(t, resolver.Resolve(ctx, name, kind, Some(int(8)), Some(Duration(time.Second))))
		if len(records.Items) == 0 {
			t.Fatalf("%s: no records", DnsKind_Text(ctx, kind))
		}
		for _, record := range records.Items {
			if DnsKind_Text(ctx, record.Kind) != DnsKind_Text(ctx, kind) {
				t.Fatalf("record kind %s; want %s", DnsKind_Text(ctx, record.Kind), DnsKind_Text(ctx, kind))
			}
		}
	}
	mx := must(t, resolver.Resolve(ctx, "test.", DnsKind_MX{}, None[int](), None[Duration]())).Items[0]
	if mx.Value != "mail.test." || mx.Priority != 10 || mx.Weight != 0 || mx.Port != 0 {
		t.Fatalf("%+v", mx)
	}
	srv := must(t, resolver.Resolve(ctx, "test.", DnsKind_SRV{}, None[int](), None[Duration]())).Items[0]
	if srv.Value != "service.test." || srv.Priority != 1 || srv.Weight != 2 || srv.Port != 443 {
		t.Fatalf("%+v", srv)
	}
	failedWith(t, resolver.Resolve(ctx, "test.", DnsKind_A{}, Some(int(0)), None[Duration]()), "NetworkError_LimitExceeded")
	addresses := must(t, resolver.Lookup(ctx, "test.", Some(int(8)), Some(Duration(time.Second))))
	if len(addresses.Items) == 0 {
		t.Fatal("lookup")
	}
	failedWith(t, resolver.Lookup(ctx, "test.", Some(int(0)), Some(Duration(time.Second))), "NetworkError_LimitExceeded")
}
