package msruntime

import (
	"context"
	"crypto/tls"
	"errors"
	"io"
	"net"
	"os"
	"strconv"
	"time"
)

func netDurationOf(d Duration) time.Duration { return time.Duration(d) }

// Connect opens a TCP connection to the first reachable permitted address.
func (n *osNetwork) Connect(ctx *Execution, address string, timeout Option[Duration]) Result[Connection, NetworkError] {
	return n.dialConnection(ctx, "tcp", address, timeout, nil)
}

// ConnectTls connects over TCP and verifies the server against system trust.
func (n *osNetwork) ConnectTls(ctx *Execution, address, serverName string, timeout Option[Duration]) Result[Connection, NetworkError] {
	if n.isClosed() {
		return netFail[Connection](errNetClosed)
	}
	if serverName == "" {
		return netFail[Connection](errNetInvalidInput)
	}
	return n.dialConnection(ctx, "tcp", address, timeout, &tls.Config{ServerName: serverName, MinVersion: tls.VersionTLS12})
}

// ConnectTlsConfig connects over TCP and handshakes with explicit options.
func (n *osNetwork) ConnectTlsConfig(ctx *Execution, address string, options *TlsOptions, timeout Option[Duration]) Result[Connection, NetworkError] {
	return n.dialConnection(ctx, "tcp", address, timeout, options)
}

// ConnectUnix connects to a Unix domain socket.
func (n *osNetwork) ConnectUnix(ctx *Execution, path string, timeout Option[Duration]) Result[Connection, NetworkError] {
	return n.dialConnection(ctx, "unix", path, timeout, nil)
}

// dialConnection dials and optionally handshakes. secure is a *tls.Config, a
// *TlsOptions (validated after dialing, as an invalid option closes the
// socket), or nil for a plain connection.
func (n *osNetwork) dialConnection(ctx *Execution, kind, address string, timeout Option[Duration], secure any) Result[Connection, NetworkError] {
	if n.isClosed() {
		return netFail[Connection](errNetClosed)
	}
	limit, ok := optTimeout(timeout)
	if !ok {
		return netFail[Connection](errNetInvalidInput)
	}
	local, cancel := timeoutContext(ctx.Context, netDurationOf(limit))
	defer cancel()
	call, finish, admitted := n.beginCall(local)
	if !admitted {
		return netFail[Connection](errNetClosed)
	}
	defer finish()
	conn, err := n.dial(call, kind, address)
	if err != nil {
		return netFail[Connection](n.failure(ctx, call, err))
	}
	switch s := secure.(type) {
	case *tls.Config:
		client := tls.Client(conn, s)
		if err := client.HandshakeContext(call); err != nil {
			conn.Close()
			return netFail[Connection](n.failure(ctx, call, err))
		}
		conn = client
	case *TlsOptions:
		config, err := tlsConfig(s, false)
		if err != nil {
			conn.Close()
			return netFail[Connection](errNetInvalidInput)
		}
		client := tls.Client(conn, config)
		if err := client.HandshakeContext(call); err != nil {
			conn.Close()
			return netFail[Connection](n.failure(ctx, call, err))
		}
		conn = client
	}
	resource := newConnection(conn, n)
	if !n.own(resource) {
		resource.closeResource(ctx)
		return netFail[Connection](errNetClosed)
	}
	return Ok[Connection, NetworkError](resource)
}

// Listen listens for TCP connections.
func (n *osNetwork) Listen(ctx *Execution, address string) Result[Listener, NetworkError] {
	return n.listen(ctx, "tcp", address, nil, netNoTimeout, false)
}

// ListenTls listens for TCP connections and handshakes each accepted one.
func (n *osNetwork) ListenTls(ctx *Execution, address string, options *TlsOptions, handshakeTimeout Option[Duration]) Result[Listener, NetworkError] {
	limit, ok := optTimeout(handshakeTimeout)
	if !ok {
		return netFail[Listener](errNetInvalidInput)
	}
	return n.listen(ctx, "tcp", address, options, limit, true)
}

// ListenUnix listens on a Unix domain socket.
func (n *osNetwork) ListenUnix(ctx *Execution, path string) Result[Listener, NetworkError] {
	return n.listen(ctx, "unix", path, nil, netNoTimeout, false)
}

func (n *osNetwork) listen(ctx *Execution, kind, address string, options *TlsOptions, handshake Duration, secure bool) Result[Listener, NetworkError] {
	if n.isClosed() {
		return netFail[Listener](errNetClosed)
	}
	if kind == "unix" {
		if n.policy != nil {
			return netFail[Listener](errNetDenied)
		}
	} else if !n.listenAllowed(address) {
		return netFail[Listener](errNetDenied)
	}
	// TLS listeners bound listening by the handshake timeout; plain Unix
	// listening by a fixed 30 seconds.
	bound := netNoTimeout
	switch {
	case secure:
		bound = handshake
	case kind == "unix":
		bound = Duration(30 * time.Second)
	}
	local, cancel := timeoutContext(ctx.Context, netDurationOf(bound))
	defer cancel()
	call, finish, admitted := n.beginCall(local)
	if !admitted {
		return netFail[Listener](errNetClosed)
	}
	defer finish()
	listener, err := (&net.ListenConfig{}).Listen(call, kind, address)
	if err != nil {
		return netFail[Listener](n.failure(ctx, call, err))
	}
	resource := &osListener{listener: listener, owner: n, gate: newGate(), life: newLifecycle()}
	if secure {
		config, err := tlsConfig(options, true)
		if err != nil {
			listener.Close()
			return netFail[Listener](errNetInvalidInput)
		}
		resource.tlsConfig = config
		resource.handshakeTimeout = netDurationOf(handshake)
	}
	if !n.own(resource) {
		listener.Close()
		return netFail[Listener](errNetClosed)
	}
	return Ok[Listener, NetworkError](resource)
}

// BindDatagram binds a UDP socket.
func (n *osNetwork) BindDatagram(ctx *Execution, address string) Result[DatagramSocket, NetworkError] {
	if n.isClosed() {
		return netFail[DatagramSocket](errNetClosed)
	}
	if !n.listenAllowed(address) {
		return netFail[DatagramSocket](errNetDenied)
	}
	call, finish, admitted := n.beginCall(ctx.Context)
	if !admitted {
		return netFail[DatagramSocket](errNetClosed)
	}
	defer finish()
	conn, err := (&net.ListenConfig{}).ListenPacket(call, "udp", address)
	if err != nil {
		CheckCancelled(ctx)
		return netFail[DatagramSocket](netFailed(describeTransportError(err)))
	}
	resource := &osDatagram{owner: n, conn: conn, read: newGate(), write: newGate(), life: newLifecycle()}
	if !n.own(resource) {
		conn.Close()
		return netFail[DatagramSocket](errNetClosed)
	}
	return Ok[DatagramSocket, NetworkError](resource)
}

// osConnection has independent read and write gates so a read and a write
// progress together; calls in one direction are serialized. Closing
// interrupts admitted I/O and waits for it.
type osConnection struct {
	owner       *osNetwork
	conn        net.Conn
	read, write gate
	life        lifecycle
}

var _ Connection = (*osConnection)(nil)

func newConnection(conn net.Conn, owner *osNetwork) *osConnection {
	return &osConnection{owner: owner, conn: conn, read: newGate(), write: newGate(), life: newLifecycle()}
}

func (c *osConnection) closeResource(*Execution) { c.close() }

func (c *osConnection) Close(*Execution) Unit { c.close(); return Unit{} }

func (c *osConnection) close() {
	if !c.life.begin() {
		return
	}
	c.conn.Close()
	c.life.finish()
	if c.owner != nil {
		c.owner.forget(c)
	}
}

func (c *osConnection) LocalAddress(*Execution) string { return c.conn.LocalAddr().String() }
func (c *osConnection) PeerAddress(*Execution) string  { return c.conn.RemoteAddr().String() }

func (c *osConnection) Read(ctx *Execution, maxBytes Option[int], timeout Option[Duration]) Result[Option[*Bytes], IoError] {
	n, okSize := optLimit(maxBytes, 65536)
	limit, okTimeout := optTimeout(timeout)
	if !okSize || !okTimeout {
		return ioFail[Option[*Bytes]](errIoInvalidInput)
	}
	s := newScope(ctx, limit)
	defer s.cancel()
	if !c.read.acquire(s.exec) {
		s.timedOut()
		return ioFail[Option[*Bytes]](ioFailed("operation timed out"))
	}
	defer c.read.release()
	if !c.life.enter() {
		return ioFail[Option[*Bytes]](errIoClosed)
	}
	defer c.life.leave()
	if n <= 0 {
		return ioFail[Option[*Bytes]](errIoInvalidInput)
	}
	if n > 65536 {
		n = 65536
	}
	stop := netInterruptDeadline(s.exec, c.conn.SetReadDeadline)
	b := make([]byte, n)
	count, err := c.conn.Read(b)
	stop()
	if s.timedOut() {
		return ioFail[Option[*Bytes]](ioFailed("operation timed out"))
	}
	if count > 0 {
		return Ok[Option[*Bytes], IoError](Some(NewBytes(b[:count])))
	}
	if err == io.EOF {
		return Ok[Option[*Bytes], IoError](None[*Bytes]())
	}
	if c.life.isClosed() {
		return ioFail[Option[*Bytes]](errIoClosed)
	}
	if err != nil {
		return ioFail[Option[*Bytes]](ioFailed(describeTransportError(err)))
	}
	return ioFail[Option[*Bytes]](ioFailed("empty read without EOF"))
}

func (c *osConnection) Write(ctx *Execution, data string, timeout Option[Duration]) Result[Unit, IoError] {
	return c.WriteBytes(ctx, NewBytes([]byte(data)), timeout)
}

func (c *osConnection) WriteBytes(ctx *Execution, data *Bytes, timeout Option[Duration]) Result[Unit, IoError] {
	limit, ok := optTimeout(timeout)
	if !ok {
		return ioFail[Unit](errIoInvalidInput)
	}
	s := newScope(ctx, limit)
	defer s.cancel()
	if !c.write.acquire(s.exec) {
		s.timedOut()
		return ioFail[Unit](ioFailed("operation timed out"))
	}
	defer c.write.release()
	if !c.life.enter() {
		return ioFail[Unit](errIoClosed)
	}
	defer c.life.leave()
	stop := netInterruptDeadline(s.exec, c.conn.SetWriteDeadline)
	defer stop()
	b := data.Data
	for len(b) > 0 {
		if s.timedOut() {
			return ioFail[Unit](ioFailed("operation timed out"))
		}
		n, err := c.conn.Write(b)
		if s.timedOut() {
			return ioFail[Unit](ioFailed("operation timed out"))
		}
		if err != nil {
			if c.life.isClosed() {
				return ioFail[Unit](errIoClosed)
			}
			return ioFail[Unit](ioFailed(describeTransportError(err)))
		}
		if n == 0 {
			return ioFail[Unit](ioFailed("short write"))
		}
		b = b[n:]
	}
	return Ok[Unit, IoError](Unit{})
}

func (c *osConnection) ShutdownWrite(ctx *Execution) Result[Unit, NetworkError] {
	c.write.mustAcquire(ctx)
	defer c.write.release()
	if !c.life.enter() {
		return netFail[Unit](errNetClosed)
	}
	defer c.life.leave()
	var err error
	switch conn := c.conn.(type) {
	case *net.UnixConn:
		err = conn.CloseWrite()
	case *net.TCPConn:
		err = conn.CloseWrite()
	case *tls.Conn:
		err = conn.CloseWrite()
	default:
		return netFail[Unit](errNetUnsupported)
	}
	if errors.Is(err, os.ErrPermission) {
		return netFail[Unit](errNetDenied)
	}
	if err != nil {
		return netFail[Unit](netFailed(describeTransportError(err)))
	}
	return Ok[Unit, NetworkError](Unit{})
}

func (c *osConnection) TlsInfo(*Execution) Result[*TlsInfo, TlsError] {
	conn, ok := c.conn.(*tls.Conn)
	if !ok {
		return Fail[*TlsInfo, TlsError](TlsError_InvalidInput{})
	}
	state := conn.ConnectionState()
	certs := []*Bytes{}
	for _, cert := range state.PeerCertificates {
		certs = append(certs, NewBytes(append([]byte{}, cert.Raw...)))
	}
	return Ok[*TlsInfo, TlsError](&TlsInfo{Version: int(state.Version), CipherSuite: int(state.CipherSuite), Alpn: state.NegotiatedProtocol, PeerCertificates: NewList(certs...), Verified: len(state.VerifiedChains) > 0})
}

// osListener accepts one connection at a time. Cancelling or timing out an
// accept leaves the listener usable.
type osListener struct {
	gate             gate
	life             lifecycle
	tlsConfig        *tls.Config
	handshakeTimeout time.Duration
	lifetime         context.Context
	cancel           context.CancelFunc
	listener         net.Listener
	owner            *osNetwork
}

var _ Listener = (*osListener)(nil)

func (l *osListener) Address(*Execution) string { return l.listener.Addr().String() }

func (l *osListener) closeResource(*Execution) { l.close() }

func (l *osListener) Close(*Execution) Unit { l.close(); return Unit{} }

func (l *osListener) close() {
	l.life.mu.Lock()
	if l.life.closed {
		done := l.life.released
		l.life.mu.Unlock()
		<-done
		return
	}
	l.life.closed = true
	if l.cancel != nil {
		l.cancel()
	}
	l.life.mu.Unlock()
	l.listener.Close()
	l.life.finish()
	l.owner.forget(l)
}

func (l *osListener) Accept(ctx *Execution, timeout Option[Duration]) Result[Connection, NetworkError] {
	limit, ok := optTimeout(timeout)
	if !ok {
		return netFail[Connection](errNetInvalidInput)
	}
	s := newScope(ctx, limit)
	defer s.cancel()
	if !l.gate.acquire(s.exec) {
		s.timedOut()
		return netFail[Connection](errNetTimeout)
	}
	defer l.gate.release()
	l.life.mu.Lock()
	if l.life.closed {
		l.life.mu.Unlock()
		return netFail[Connection](errNetClosed)
	}
	if l.lifetime == nil {
		l.lifetime, l.cancel = context.WithCancel(context.Background())
	}
	l.life.active.Add(1)
	lifetime := l.lifetime
	l.life.mu.Unlock()
	defer l.life.active.Done()
	call, cancel := context.WithCancel(s.exec.Context)
	defer cancel()
	stopClose := context.AfterFunc(lifetime, cancel)
	defer stopClose()
	setDeadline := func(t time.Time) error {
		switch listener := l.listener.(type) {
		case *net.TCPListener:
			return listener.SetDeadline(t)
		case *net.UnixListener:
			return listener.SetDeadline(t)
		}
		return net.ErrClosed
	}
	stopDeadline := netInterruptDeadline(netChild(ctx, call), setDeadline)
	conn, err := l.listener.Accept()
	stopDeadline()
	if err != nil {
		CheckCancelled(ctx)
		if l.life.isClosed() {
			return netFail[Connection](errNetClosed)
		}
		if call.Err() != nil {
			return netFail[Connection](errNetTimeout)
		}
		return netFail[Connection](netFailed(describeTransportError(err)))
	}
	if l.tlsConfig != nil {
		secure := tls.Server(conn, l.tlsConfig)
		handshake, done := timeoutContext(call, l.handshakeTimeout)
		err = secure.HandshakeContext(handshake)
		done()
		if err != nil {
			conn.Close()
			if s.timedOut() {
				return netFail[Connection](errNetTimeout)
			}
			return netFail[Connection](netFailed(describeTransportError(err)))
		}
		conn = secure
	}
	resource := newConnection(conn, l.owner)
	if !l.owner.own(resource) {
		resource.close()
		return netFail[Connection](errNetClosed)
	}
	return Ok[Connection, NetworkError](resource)
}

// osDatagram preserves message boundaries; receive and send have their own
// gates.
type osDatagram struct {
	lifetime    context.Context
	cancel      context.CancelFunc
	owner       *osNetwork
	conn        net.PacketConn
	read, write gate
	life        lifecycle
}

var _ DatagramSocket = (*osDatagram)(nil)

func (d *osDatagram) Address(*Execution) string { return d.conn.LocalAddr().String() }

func (d *osDatagram) closeResource(*Execution) { d.close() }

func (d *osDatagram) Close(*Execution) Unit { d.close(); return Unit{} }

func (d *osDatagram) close() {
	d.life.mu.Lock()
	if d.life.closed {
		done := d.life.released
		d.life.mu.Unlock()
		<-done
		return
	}
	d.life.closed = true
	if d.cancel != nil {
		d.cancel()
	}
	d.life.mu.Unlock()
	d.conn.Close()
	d.life.finish()
	d.owner.forget(d)
}

func (d *osDatagram) Receive(ctx *Execution, maxBytes Option[int], timeout Option[Duration]) Result[*Datagram, NetworkError] {
	max, okSize := optLimit(maxBytes, 65535)
	limit, okTimeout := optTimeout(timeout)
	if !okSize || !okTimeout {
		return netFail[*Datagram](errNetInvalidInput)
	}
	s := newScope(ctx, limit)
	defer s.cancel()
	if !d.read.acquire(s.exec) {
		s.timedOut()
		return netFail[*Datagram](errNetTimeout)
	}
	defer d.read.release()
	if !d.life.enter() {
		return netFail[*Datagram](errNetClosed)
	}
	defer d.life.leave()
	if max <= 0 || max > 65535 {
		return netFail[*Datagram](errNetInvalidInput)
	}
	stop := netInterruptDeadline(s.exec, d.conn.SetReadDeadline)
	b := make([]byte, max+1)
	count, from, err := d.conn.ReadFrom(b)
	stop()
	if s.timedOut() {
		return netFail[*Datagram](errNetTimeout)
	}
	if err != nil {
		if d.life.isClosed() {
			return netFail[*Datagram](errNetClosed)
		}
		return netFail[*Datagram](netFailed(describeTransportError(err)))
	}
	if int(count) > max {
		return netFail[*Datagram](errNetLimit)
	}
	return Ok[*Datagram, NetworkError](&Datagram{Data: NewBytes(b[:count]), Sender: from.String()})
}

func (d *osDatagram) Send(ctx *Execution, data string, address string, timeout Option[Duration]) Result[Unit, NetworkError] {
	return d.SendBytes(ctx, NewBytes([]byte(data)), address, timeout)
}

func (d *osDatagram) SendBytes(ctx *Execution, data *Bytes, address string, timeout Option[Duration]) Result[Unit, NetworkError] {
	limit, ok := optTimeout(timeout)
	if !ok {
		return netFail[Unit](errNetInvalidInput)
	}
	s := newScope(ctx, limit)
	defer s.cancel()
	if !d.write.acquire(s.exec) {
		s.timedOut()
		return netFail[Unit](errNetTimeout)
	}
	defer d.write.release()
	if !d.life.enter() {
		return netFail[Unit](errNetClosed)
	}
	defer d.life.leave()
	target, err := d.resolve(s.exec, address)
	if s.timedOut() {
		return netFail[Unit](errNetTimeout)
	}
	if err != nil {
		if errors.Is(err, net.ErrClosed) || d.owner.isClosed() {
			return netFail[Unit](errNetClosed)
		}
		if errors.Is(err, os.ErrPermission) {
			return netFail[Unit](errNetDenied)
		}
		return netFail[Unit](netFailed(describeTransportError(err)))
	}
	stop := netInterruptDeadline(s.exec, d.conn.SetWriteDeadline)
	n, err := d.conn.WriteTo(data.Data, target)
	stop()
	if s.timedOut() {
		return netFail[Unit](errNetTimeout)
	}
	if err != nil {
		return netFail[Unit](netFailed(describeTransportError(err)))
	}
	if n != len(data.Data) {
		return netFail[Unit](netFailed("partial datagram"))
	}
	return Ok[Unit, NetworkError](Unit{})
}

// resolve turns host:port into a permitted UDP address, cancellably.
func (d *osDatagram) resolve(ctx *Execution, address string) (*net.UDPAddr, error) {
	d.life.mu.Lock()
	if d.life.closed {
		d.life.mu.Unlock()
		return nil, net.ErrClosed
	}
	if d.lifetime == nil {
		d.lifetime, d.cancel = context.WithCancel(context.Background())
	}
	lifetime := d.lifetime
	d.life.mu.Unlock()
	local, cancel := context.WithCancel(ctx.Context)
	defer cancel()
	stop := context.AfterFunc(lifetime, cancel)
	defer stop()
	call, finish, ok := d.owner.beginCall(local)
	if !ok {
		return nil, net.ErrClosed
	}
	defer finish()
	host, portText, err := net.SplitHostPort(address)
	if err != nil {
		return nil, err
	}
	port, err := strconv.Atoi(portText)
	if err != nil || port < 0 || port > 65535 {
		return nil, errors.New("invalid port")
	}
	if !d.owner.policy.host(host) {
		return nil, os.ErrPermission
	}
	ips, err := d.owner.resolverInstance().LookupNetIP(call, "ip", host)
	if err != nil {
		if d.life.isClosed() {
			return nil, net.ErrClosed
		}
		return nil, err
	}
	for _, ip := range ips {
		if d.owner.policy.ip(ip) {
			return &net.UDPAddr{IP: net.IP(ip.AsSlice()), Port: port, Zone: ip.Zone()}, nil
		}
	}
	return nil, os.ErrPermission
}
