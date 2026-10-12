package msruntime

import (
	"context"
	"crypto/tls"
	"errors"
	"io"
	"net"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"
)

func init() {
	for _, m := range []LibraryMethod{
		{"Network", "connect", libraryResult("Connection&Shareable", "NetworkError"), []LibraryParam{{"address", "String"}, {"timeout", "Duration"}}},
		{"Network", "connect_tls", libraryResult("Connection&Shareable", "NetworkError"), []LibraryParam{{"address", "String"}, {"server_name", "String"}, {"timeout", "Duration"}}},
		{"Network", "listen", libraryResult("Listener&Shareable", "NetworkError"), []LibraryParam{{"address", "String"}}},
		{"Network", "bind_datagram", libraryResult("DatagramSocket&Shareable", "NetworkError"), []LibraryParam{{"address", "String"}}},
		{"Connection", "read", "Result[Optional[Bytes]][IoError]", []LibraryParam{{"max_bytes", "Int"}}},
		{"Connection", "write", "Result[Unit][IoError]", []LibraryParam{{"data", "Bytes"}}},
		{"Connection", "shutdown_write", libraryResult("Unit", "NetworkError"), nil},
		{"Connection", "local_address", "String", nil}, {"Connection", "peer_address", "String", nil}, {"Connection", "close", "Unit", nil},
		{"Listener", "accept", libraryResult("Connection&Shareable", "NetworkError"), nil}, {"Listener", "address", "String", nil}, {"Listener", "close", "Unit", nil},
		{"DatagramSocket", "send", libraryResult("Unit", "NetworkError"), []LibraryParam{{"data", "Bytes"}, {"address", "String"}}},
		{"DatagramSocket", "receive", libraryResult("Datagram", "NetworkError"), []LibraryParam{{"max_bytes", "Int"}}},
		{"DatagramSocket", "address", "String", nil}, {"DatagramSocket", "close", "Unit", nil},
	} {
		LibraryMethods = append(LibraryMethods, m)
	}
}
func libraryAcquisition(receiver, name string, body func(*Execution, string, []Value) Value) Function {
	f := libraryMethod(receiver, name, body)
	return NewAcquisition(f.Labels, f.Result, func(ctx *Execution, a []Value) Value { return body(ctx, f.Result, a) }, func(ctx *Execution, v Value) {
		alt := v.(Alternative)
		if alt.Tag == "ok" {
			Invoke(Shield(ctx), Bind(alt.Fields[0], "", "close"), nil)
		}
	})
}
func libraryNetworkAcquire(n *network, name string) Function {
	return libraryAcquisition("Network", name, func(ctx *Execution, r string, a []Value) Value {
		n.mu.Lock()
		closed := n.closed
		n.mu.Unlock()
		if closed {
			return libraryError(r, "Closed", "")
		}
		address := a[0].(string)
		switch name {
		case "connect", "connect_tls":
			timeout := a[len(a)-1].(Duration)
			if timeout < 0 {
				return libraryError(r, "InvalidInput", "")
			}
			call, cancel := contextWithLibraryTimeout(ctx, timeout)
			defer cancel()
			call, finish, admitted := n.beginCall(call)
			if !admitted {
				return libraryError(r, "Closed", "")
			}
			defer finish()
			var conn net.Conn
			var err error
			if name == "connect_tls" {
				serverName := a[1].(string)
				if serverName == "" {
					return libraryError(r, "InvalidInput", "")
				}
				conn, err = n.dial(call, "tcp", address)
				if err == nil {
					secure := tls.Client(conn, &tls.Config{ServerName: serverName, MinVersion: tls.VersionTLS12})
					err = secure.HandshakeContext(call)
					if err != nil {
						conn.Close()
					} else {
						conn = secure
					}
				}
			} else {
				conn, err = n.dial(call, "tcp", address)
			}
			if err != nil {
				return n.networkFailure(ctx, r, call, err)
			}
			resource := newLibraryConnection(conn)
			resource.owner = n
			n.mu.Lock()
			if n.closed {
				n.mu.Unlock()
				conn.Close()
				return libraryError(r, "Closed", "")
			}
			n.resources = append(n.resources, resource)
			n.mu.Unlock()
			return libraryOK(r, ViewOf("@std/Connection&Shareable", resource))
		case "listen":
			if !n.listenAllowed(address) {
				return libraryError(r, "PermissionDenied", "")
			}
			call, finish, admitted := n.beginCall(ctx.Context)
			if !admitted {
				return libraryError(r, "Closed", "")
			}
			defer finish()
			config := net.ListenConfig{}
			listener, err := config.Listen(call, "tcp", address)
			if err != nil {
				CheckCancelled(ctx)
				return libraryError(r, "Failed", err.Error())
			}
			resource := &libraryListener{listener: listener, owner: n, gate: make(chan struct{}, 1), released: make(chan struct{})}
			resource.gate <- struct{}{}
			n.mu.Lock()
			if n.closed {
				n.mu.Unlock()
				listener.Close()
				return libraryError(r, "Closed", "")
			}
			n.resources = append(n.resources, resource)
			n.mu.Unlock()
			return libraryOK(r, ViewOf("@std/Listener&Shareable", resource))
		case "bind_datagram":
			if !n.listenAllowed(address) {
				return libraryError(r, "PermissionDenied", "")
			}
			call, finish, admitted := n.beginCall(ctx.Context)
			if !admitted {
				return libraryError(r, "Closed", "")
			}
			defer finish()
			config := net.ListenConfig{}
			conn, err := config.ListenPacket(call, "udp", address)
			if err != nil {
				CheckCancelled(ctx)
				return libraryError(r, "Failed", err.Error())
			}
			resource := &libraryDatagram{owner: n, conn: conn, read: make(chan struct{}, 1), write: make(chan struct{}, 1)}
			resource.read <- struct{}{}
			resource.write <- struct{}{}
			n.mu.Lock()
			if n.closed {
				n.mu.Unlock()
				conn.Close()
				return libraryError(r, "Closed", "")
			}
			n.resources = append(n.resources, resource)
			n.mu.Unlock()
			return libraryOK(r, ViewOf("@std/DatagramSocket&Shareable", resource))
		}
		return Panic("unknown network acquisition")
	})
}

// Independent read/write gates preserve duplex progress. Closing interrupts admitted
// I/O and waits for it; gate waiters check closed state before using the handle.
type libraryConnection struct {
	owner       *network
	conn        net.Conn
	mu          sync.Mutex
	closed      bool
	active      sync.WaitGroup
	read, write chan struct{}
	released    chan struct{}
}

func newLibraryConnection(conn net.Conn) *libraryConnection {
	c := &libraryConnection{conn: conn, read: make(chan struct{}, 1), write: make(chan struct{}, 1), released: make(chan struct{})}
	c.read <- struct{}{}
	c.write <- struct{}{}
	return c
}
func (c *libraryConnection) close() {
	c.mu.Lock()
	if c.closed {
		done := c.released
		c.mu.Unlock()
		<-done
		return
	}
	c.closed = true
	c.mu.Unlock()
	c.conn.Close()
	c.active.Wait()
	close(c.released)
	if c.owner != nil {
		c.owner.forgetResource(c)
	}
}
func libraryGate(ctx *Execution, gate chan struct{}) {
	select {
	case <-gate:
	case <-ctx.Context.Done():
		CheckCancelled(ctx)
	}
}
func libraryInterrupt(ctx *Execution, deadline func(time.Time) error) func() {
	done := make(chan struct{})
	stop := context.AfterFunc(ctx.Context, func() { defer close(done); deadline(time.Now()) })
	return func() {
		if !stop() {
			<-done
		}
		deadline(time.Time{})
	}
}
func (c *libraryConnection) Operation(name string) Function {
	if name == "tls_info" {
		return c.tlsInfo()
	}
	if name == "read_timeout" || name == "write_timeout" {
		base := strings.TrimSuffix(name, "_timeout")
		return libraryTimeoutMethod("Connection", name, base, c.Operation(base))
	}
	return libraryMethod("Connection", name, func(ctx *Execution, r string, a []Value) Value {
		if name == "close" {
			c.close()
			return Unit{}
		}
		if name == "local_address" {
			return c.conn.LocalAddr().String()
		}
		if name == "peer_address" {
			return c.conn.RemoteAddr().String()
		}
		gate := c.read
		if name != "read" {
			gate = c.write
		}
		libraryGate(ctx, gate)
		defer func() { gate <- struct{}{} }()
		c.mu.Lock()
		if c.closed {
			c.mu.Unlock()
			if name == "read" || name == "write" {
				return ioError(r, "Closed", "")
			}
			return libraryError(r, "Closed", "")
		}
		c.active.Add(1)
		c.mu.Unlock()
		defer c.active.Done()
		if name == "shutdown_write" {
			var err error
			switch conn := c.conn.(type) {
			case *net.UnixConn:
				err = conn.CloseWrite()
			case *net.TCPConn:
				err = conn.CloseWrite()
			case *tls.Conn:
				err = conn.CloseWrite()
			default:
				return libraryError(r, "Unsupported", "")
			}
			if errors.Is(err, os.ErrPermission) {
				return libraryError(r, "PermissionDenied", "")
			}
			if err != nil {
				return libraryError(r, "Failed", err.Error())
			}
			return libraryOK(r, Unit{})
		}
		if name == "read" {
			n := a[0].(int64)
			if n <= 0 {
				return ioError(r, "InvalidInput", "")
			}
			if n > 65536 {
				n = 65536
			}
			defer libraryInterrupt(ctx, c.conn.SetReadDeadline)()
			b := make([]byte, n)
			count, err := c.conn.Read(b)
			CheckCancelled(ctx)
			if count > 0 {
				return libraryOK(r, optional("@std/Bytes", Bytes{b[:count]}, true))
			}
			if err == io.EOF {
				return libraryOK(r, optional("@std/Bytes", nil, false))
			}
			c.mu.Lock()
			closed := c.closed
			c.mu.Unlock()
			if closed {
				return ioError(r, "Closed", "")
			}
			if err != nil {
				return ioError(r, "Failed", err.Error())
			}
			return ioError(r, "Failed", "empty read without EOF")
		}
		defer libraryInterrupt(ctx, c.conn.SetWriteDeadline)()
		b := a[0].(Bytes).Items
		for len(b) > 0 {
			CheckCancelled(ctx)
			n, err := c.conn.Write(b)
			CheckCancelled(ctx)
			if err != nil {
				c.mu.Lock()
				closed := c.closed
				c.mu.Unlock()
				if closed {
					return ioError(r, "Closed", "")
				}
				return ioError(r, "Failed", err.Error())
			}
			if n == 0 {
				return ioError(r, "Failed", "short write")
			}
			b = b[n:]
		}
		return libraryOK(r, Unit{})
	})
}

type libraryListener struct {
	gate             chan struct{}
	released         chan struct{}
	tlsConfig        *tls.Config
	handshakeTimeout time.Duration
	lifetime         context.Context
	cancel           context.CancelFunc
	listener         net.Listener
	owner            *network
	mu               sync.Mutex
	closed           bool
	active           sync.WaitGroup
}

func (l *libraryListener) Operation(name string) Function {
	if name == "accept_timeout" {
		return libraryTimeoutMethod("Listener", name, "accept", l.Operation("accept"))
	}
	if name == "accept" {
		return libraryAcquisition("Listener", name, func(ctx *Execution, r string, _ []Value) Value {
			libraryGate(ctx, l.gate)
			defer func() { l.gate <- struct{}{} }()
			l.mu.Lock()
			if l.closed {
				l.mu.Unlock()
				return libraryError(r, "Closed", "")
			}
			if l.lifetime == nil {
				l.lifetime, l.cancel = context.WithCancel(context.Background())
			}
			l.active.Add(1)
			lifetime := l.lifetime
			l.mu.Unlock()
			defer l.active.Done()
			call, cancel := context.WithCancel(ctx.Context)
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
			execution := inherit(ctx, call)
			defer libraryInterrupt(execution, setDeadline)()
			conn, err := l.listener.Accept()
			if err != nil {
				CheckCancelled(ctx)
				l.mu.Lock()
				closed := l.closed
				l.mu.Unlock()
				if closed {
					return libraryError(r, "Closed", "")
				}
				if call.Err() != nil {
					return libraryError(r, "Timeout", "")
				}
				return libraryError(r, "Failed", err.Error())
			}
			if l.tlsConfig != nil {
				secure := tls.Server(conn, l.tlsConfig)
				handshake, done := context.WithTimeout(call, l.handshakeTimeout)
				err = secure.HandshakeContext(handshake)
				done()
				if err != nil {
					conn.Close()
					CheckCancelled(ctx)
					return libraryError(r, "Failed", err.Error())
				}
				conn = secure
			}
			resource := newLibraryConnection(conn)
			resource.owner = l.owner
			if !l.owner.own(resource) {
				resource.close()
				return libraryError(r, "Closed", "")
			}
			return libraryOK(r, ViewOf("@std/Connection&Shareable", resource))
		})
	}
	return libraryMethod("Listener", name, func(_ *Execution, _ string, _ []Value) Value {
		if name == "address" {
			return l.listener.Addr().String()
		}
		l.mu.Lock()
		if l.closed {
			done := l.released
			l.mu.Unlock()
			<-done
			return Unit{}
		}
		l.closed = true
		if l.cancel != nil {
			l.cancel()
		}
		l.mu.Unlock()
		l.listener.Close()
		l.active.Wait()
		l.owner.forgetResource(l)
		close(l.released)
		return Unit{}
	})
}

func errorsIsNetClosed(err error) bool { return errors.Is(err, net.ErrClosed) }

type libraryDatagram struct {
	lifetime    context.Context
	cancel      context.CancelFunc
	released    chan struct{}
	owner       *network
	conn        net.PacketConn
	mu          sync.Mutex
	closed      bool
	active      sync.WaitGroup
	read, write chan struct{}
}

func (d *libraryDatagram) Operation(name string) Function {
	if name == "send_timeout" || name == "receive_timeout" {
		base := strings.TrimSuffix(name, "_timeout")
		return libraryTimeoutMethod("DatagramSocket", name, base, d.Operation(base))
	}
	return libraryMethod("DatagramSocket", name, func(ctx *Execution, r string, a []Value) Value {
		if name == "address" {
			return d.conn.LocalAddr().String()
		}
		if name == "close" {
			d.mu.Lock()
			if d.closed {
				done := d.released
				d.mu.Unlock()
				if done != nil {
					<-done
				}
				return Unit{}
			}
			d.released = make(chan struct{})
			if d.cancel != nil {
				d.cancel()
			}
			d.closed = true
			d.mu.Unlock()
			d.conn.Close()
			d.active.Wait()
			d.owner.forgetResource(d)
			close(d.released)
			return Unit{}
		}
		gate := d.read
		if name == "send" {
			gate = d.write
		}
		libraryGate(ctx, gate)
		defer func() { gate <- struct{}{} }()
		d.mu.Lock()
		if d.closed {
			d.mu.Unlock()
			return libraryError(r, "Closed", "")
		}
		d.active.Add(1)
		d.mu.Unlock()
		defer d.active.Done()
		if name == "send" {
			address, err := d.resolve(ctx, a[1].(string))
			CheckCancelled(ctx)
			if err != nil {
				if errors.Is(err, net.ErrClosed) || d.owner.isClosed() {
					return libraryError(r, "Closed", "")
				}
				if errors.Is(err, os.ErrPermission) {
					return libraryError(r, "PermissionDenied", "")
				}
				return libraryError(r, "Failed", err.Error())
			}
			defer libraryInterrupt(ctx, d.conn.SetWriteDeadline)()
			b := a[0].(Bytes).Items
			n, err := d.conn.WriteTo(b, address)
			CheckCancelled(ctx)
			if err != nil {
				return libraryError(r, "Failed", err.Error())
			}
			if n != len(b) {
				return libraryError(r, "Failed", "partial datagram")
			}
			return libraryOK(r, Unit{})
		}
		max := a[0].(int64)
		if max <= 0 || max > 65535 {
			return libraryError(r, "InvalidInput", "")
		}
		defer libraryInterrupt(ctx, d.conn.SetReadDeadline)()
		b := make([]byte, max+1)
		count, from, err := d.conn.ReadFrom(b)
		CheckCancelled(ctx)
		if err != nil {
			d.mu.Lock()
			closed := d.closed
			d.mu.Unlock()
			if closed {
				return libraryError(r, "Closed", "")
			}
			return libraryError(r, "Failed", err.Error())
		}
		if int64(count) > max {
			return libraryError(r, "LimitExceeded", "")
		}
		return libraryOK(r, Record{"@std/Datagram", map[string]Value{"data": Bytes{b[:count]}, "sender": from.String()}})
	})
}

func (n *network) forgetResource(resource Value) {
	n.mu.Lock()
	defer n.mu.Unlock()
	for i, v := range n.resources {
		if v == resource {
			n.resources = append(n.resources[:i], n.resources[i+1:]...)
			return
		}
	}
}

type libraryNetworkCall struct{ cancel context.CancelFunc }

func (n *network) beginCall(parent context.Context) (context.Context, func(), bool) {
	n.mu.Lock()
	defer n.mu.Unlock()
	if n.closed {
		return nil, nil, false
	}
	ctx, cancel := context.WithCancel(parent)
	call := &libraryNetworkCall{cancel}
	if n.calls == nil {
		n.calls = map[*libraryNetworkCall]bool{}
	}
	n.calls[call] = true
	n.active.Add(1)
	return ctx, func() { cancel(); n.mu.Lock(); delete(n.calls, call); n.mu.Unlock(); n.active.Done() }, true
}
func (n *network) isClosed() bool { n.mu.Lock(); defer n.mu.Unlock(); return n.closed }

func libraryTimeoutMethod(receiver, name, base string, operation Function) Function {
	return libraryMethod(receiver, name, func(ctx *Execution, r string, a []Value) (value Value) {
		timeout := a[len(a)-1].(Duration)
		if timeout < 0 {
			if receiver == "Connection" {
				return ioError(r, "InvalidInput", "")
			}
			return libraryError(r, "InvalidInput", "")
		}
		local, cancel := contextWithLibraryTimeout(ctx, timeout)
		defer cancel()
		defer func() {
			if recovered := recover(); recovered != nil {
				if _, ok := recovered.(cancelled); !ok {
					panic(recovered)
				}
				CheckCancelled(ctx)
				if receiver == "Connection" {
					value = ioError(r, "Failed", "operation timed out")
				} else {
					value = libraryError(r, "Timeout", "")
				}
			}
		}()
		return operation.Body(inherit(ctx, local), a[:len(a)-1])
	})
}
func (d *libraryDatagram) resolve(ctx *Execution, address string) (*net.UDPAddr, error) {
	d.mu.Lock()
	if d.closed {
		d.mu.Unlock()
		return nil, net.ErrClosed
	}
	if d.lifetime == nil {
		d.lifetime, d.cancel = context.WithCancel(context.Background())
	}
	lifetime := d.lifetime
	d.mu.Unlock()
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
		d.mu.Lock()
		closed := d.closed
		d.mu.Unlock()
		if closed {
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
