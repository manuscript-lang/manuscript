package msruntime

import (
	"context"
	"errors"
	"net"
	"net/netip"
	"os"
	"strings"
	"sync"
	"unicode/utf8"
)

// IpAddress is a validated numeric IPv4 or IPv6 address without a port or
// zone. It holds no resource and is never reparsed.
type IpAddress struct{ addr netip.Addr }

// Cidr is a validated, masked numeric CIDR range.
type Cidr struct{ prefix netip.Prefix }

// Net_ParseIp validates and canonicalizes an address. Zones are rejected and
// IPv4-mapped IPv6 input is normalized to IPv4.
func Net_ParseIp(_ *Execution, text string) Result[*IpAddress, NetworkError] {
	ip := net.ParseIP(text)
	if ip == nil {
		return netFail[*IpAddress](errNetInvalidData)
	}
	if v4 := ip.To4(); v4 != nil {
		ip = v4
	}
	address, _ := netip.AddrFromSlice(ip)
	return Ok[*IpAddress, NetworkError](&IpAddress{address})
}

// Net_ParseCidr validates and canonicalizes a CIDR range.
func Net_ParseCidr(_ *Execution, text string) Result[*Cidr, NetworkError] {
	prefix, err := netip.ParsePrefix(text)
	if err != nil {
		return netFail[*Cidr](errNetInvalidData)
	}
	return Ok[*Cidr, NetworkError](&Cidr{prefix.Masked()})
}

// Net_ContainsIp reports whether the address belongs to the range.
func Net_ContainsIp(_ *Execution, cidr *Cidr, address *IpAddress) Result[bool, NetworkError] {
	return Ok[bool, NetworkError](cidr.prefix.Contains(address.addr))
}

// IpAddress_Text returns canonical text.
func IpAddress_Text(_ *Execution, a *IpAddress) string { return a.addr.String() }

// IpAddress_Family returns the normalized address family.
func IpAddress_Family(_ *Execution, a *IpAddress) IpFamily {
	if a.addr.Is4() {
		return IpFamily_IPv4{}
	}
	return IpFamily_IPv6{}
}

// Cidr_Text returns the canonical masked prefix.
func Cidr_Text(_ *Execution, c *Cidr) string { return c.prefix.String() }

// IpFamily_Text returns IPv4 or IPv6.
func IpFamily_Text(_ *Execution, f IpFamily) string {
	if _, v4 := f.(IpFamily_IPv4); v4 {
		return "IPv4"
	}
	return "IPv6"
}

// DnsKind_Text returns the uppercase wire category.
func DnsKind_Text(_ *Execution, k DnsKind) string {
	switch k.(type) {
	case DnsKind_A:
		return "A"
	case DnsKind_AAAA:
		return "AAAA"
	case DnsKind_CNAME:
		return "CNAME"
	case DnsKind_MX:
		return "MX"
	case DnsKind_NS:
		return "NS"
	case DnsKind_TXT:
		return "TXT"
	case DnsKind_PTR:
		return "PTR"
	case DnsKind_SRV:
		return "SRV"
	}
	return ""
}

var hostNetworkMu sync.Mutex

// Net_Network returns the network service of the current host. Repeated calls
// return the same root; an unwired host gets an OS-backed network.
func Net_Network(ctx *Execution) Network {
	hostNetworkMu.Lock()
	defer hostNetworkMu.Unlock()
	host := ctx.State.Host
	if host.Network == nil {
		host.Network = NewOSNetwork()
	}
	return host.Network
}

// netResource is a handle a Network owns and closes with itself.
type netResource interface{ closeResource(ctx *Execution) }

// networkPolicy narrows what a network may reach. A nil policy allows all.
type networkPolicy struct {
	hosts    map[string]bool
	prefixes []netip.Prefix
	listen   bool
	parent   *networkPolicy
}

func (p *networkPolicy) host(name string) bool {
	if p == nil {
		return true
	}
	name = strings.ToLower(strings.TrimSuffix(name, "."))
	allowed := p.hosts[name]
	if ip, err := netip.ParseAddr(name); err == nil {
		for _, prefix := range p.prefixes {
			if prefix.Contains(ip.Unmap()) {
				allowed = true
				break
			}
		}
	}
	return allowed && (p.parent == nil || p.parent.host(name))
}

func (p *networkPolicy) ip(ip netip.Addr) bool {
	if p == nil {
		return true
	}
	ip = ip.Unmap()
	allowed := len(p.prefixes) == 0 && len(p.hosts) > 0
	for _, prefix := range p.prefixes {
		if prefix.Contains(ip) {
			allowed = true
			break
		}
	}
	return allowed && (p.parent == nil || p.parent.ip(ip))
}

// osNetwork is the OS-backed Network. Derived networks share its ownership
// tree: closing a network closes everything it and its children opened.
type osNetwork struct {
	mu        sync.Mutex
	policy    *networkPolicy
	resolver  *net.Resolver
	parent    *osNetwork
	released  chan struct{}
	servers   []*httpServer
	resources []netResource
	closed    bool
	calls     map[*netCall]bool
	active    sync.WaitGroup
}

var _ Network = (*osNetwork)(nil)

// NewOSNetwork returns an unrestricted network over the host's sockets and
// system resolver.
func NewOSNetwork() Network { return &osNetwork{} }

type netCall struct{ cancel context.CancelFunc }

// beginCall registers an in-flight call that Close cancels and joins.
func (n *osNetwork) beginCall(parent context.Context) (context.Context, func(), bool) {
	n.mu.Lock()
	defer n.mu.Unlock()
	if n.closed {
		return nil, nil, false
	}
	ctx, cancel := context.WithCancel(parent)
	call := &netCall{cancel}
	if n.calls == nil {
		n.calls = map[*netCall]bool{}
	}
	n.calls[call] = true
	n.active.Add(1)
	return ctx, func() { cancel(); n.mu.Lock(); delete(n.calls, call); n.mu.Unlock(); n.active.Done() }, true
}

func (n *osNetwork) isClosed() bool { n.mu.Lock(); defer n.mu.Unlock(); return n.closed }

// own registers a resource; it reports false when the network is closed.
func (n *osNetwork) own(r netResource) bool {
	n.mu.Lock()
	defer n.mu.Unlock()
	if n.closed {
		return false
	}
	n.resources = append(n.resources, r)
	return true
}

func (n *osNetwork) forget(r netResource) {
	n.mu.Lock()
	defer n.mu.Unlock()
	for i, v := range n.resources {
		if v == r {
			n.resources = append(n.resources[:i], n.resources[i+1:]...)
			return
		}
	}
}

func (n *osNetwork) resolverInstance() *net.Resolver {
	if n.resolver != nil {
		return n.resolver
	}
	return net.DefaultResolver
}

// dial connects through the policy, checking every resolved address.
func (n *osNetwork) dial(ctx context.Context, kind, address string) (net.Conn, error) {
	if kind == "unix" {
		if n.policy != nil {
			return nil, os.ErrPermission
		}
		return (&net.Dialer{}).DialContext(ctx, kind, address)
	}
	host, port, err := net.SplitHostPort(address)
	if err != nil {
		return nil, err
	}
	if !n.policy.host(host) {
		return nil, os.ErrPermission
	}
	ips, err := n.resolverInstance().LookupNetIP(ctx, "ip", host)
	if err != nil {
		return nil, err
	}
	var last error = errors.New("no permitted address")
	for _, ip := range ips {
		if !n.policy.ip(ip) {
			last = os.ErrPermission
			continue
		}
		conn, err := (&net.Dialer{}).DialContext(ctx, kind, net.JoinHostPort(ip.String(), port))
		if err == nil {
			return conn, nil
		}
		last = err
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
	}
	return nil, last
}

func (n *osNetwork) listenAllowed(address string) bool {
	if n.policy == nil {
		return true
	}
	if !n.policy.listen {
		return false
	}
	host, _, err := net.SplitHostPort(address)
	if err != nil {
		return false
	}
	ip, err := netip.ParseAddr(host)
	return err == nil && n.policy.ip(ip)
}

// failure maps a host error to the NetworkError a call reports. A cancelled
// task unwinds instead.
func (n *osNetwork) failure(ctx *Execution, call context.Context, err error) NetworkError {
	CheckCancelled(ctx)
	if n.isClosed() {
		return errNetClosed
	}
	if call != nil && call.Err() != nil {
		return errNetTimeout
	}
	if errors.Is(err, os.ErrPermission) {
		return errNetDenied
	}
	if errors.Is(err, net.ErrClosed) {
		return errNetClosed
	}
	if e, ok := err.(net.Error); ok && e.Timeout() {
		return errNetTimeout
	}
	return netFailed(err.Error())
}

// Close cancels in-flight calls and closes everything this network opened.
func (n *osNetwork) Close(ctx *Execution) Unit {
	if inService(ctx, func(s *httpServer) bool { return s.owner == n }) {
		Raise("network cannot close from its own request")
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
		defer n.parent.forget(n)
	}
	servers := append([]*httpServer{}, n.servers...)
	resources := append([]netResource{}, n.resources...)
	for call := range n.calls {
		call.cancel()
	}
	n.mu.Unlock()
	defer n.active.Wait()
	// Innermost first: servers, then resources, each in reverse order.
	var failures []any
	closeOne := func(r netResource) {
		defer func() {
			if failure := recover(); failure != nil {
				failures = append(failures, failure)
			}
		}()
		r.closeResource(Shield(ctx))
	}
	for i := len(servers) - 1; i >= 0; i-- {
		closeOne(servers[i])
	}
	for i := len(resources) - 1; i >= 0; i-- {
		closeOne(resources[i])
	}
	if len(failures) > 0 {
		panic(joinFaults(failures))
	}
	return Unit{}
}

func (n *osNetwork) closeResource(ctx *Execution) { n.Close(ctx) }

// Restrict returns a derived network limited to hosts and CIDR ranges.
func (n *osNetwork) Restrict(_ *Execution, hosts, cidrs *List[string], allowListen bool) Result[Network, NetworkError] {
	child := &osNetwork{policy: n.policy, resolver: n.resolver, parent: n}
	p := &networkPolicy{hosts: map[string]bool{}, listen: allowListen, parent: n.policy}
	for _, host := range stringItems(hosts) {
		if host == "" || strings.ContainsAny(host, "/\\\x00 :") {
			return netFail[Network](errNetInvalidInput)
		}
		p.hosts[strings.ToLower(strings.TrimSuffix(host, "."))] = true
	}
	for _, text := range stringItems(cidrs) {
		prefix, err := netip.ParsePrefix(text)
		if err != nil {
			return netFail[Network](errNetInvalidInput)
		}
		p.prefixes = append(p.prefixes, prefix.Masked())
	}
	child.policy = p
	if !n.own(child) {
		return netFail[Network](errNetClosed)
	}
	return Ok[Network, NetworkError](child)
}

// WithResolver returns a derived network that resolves through the DNS server
// at address.
func (n *osNetwork) WithResolver(_ *Execution, address string) Result[Network, NetworkError] {
	child := &osNetwork{policy: n.policy, resolver: n.resolver, parent: n}
	host, _, err := net.SplitHostPort(address)
	ip, e := netip.ParseAddr(host)
	if err != nil || e != nil {
		return netFail[Network](errNetInvalidInput)
	}
	if !n.policy.host(host) || !n.policy.ip(ip) {
		return netFail[Network](errNetDenied)
	}
	child.resolver = &net.Resolver{PreferGo: true, Dial: func(ctx context.Context, kind, _ string) (net.Conn, error) {
		return (&net.Dialer{}).DialContext(ctx, kind, address)
	}}
	if !n.own(child) {
		return netFail[Network](errNetClosed)
	}
	return Ok[Network, NetworkError](child)
}

// Lookup resolves a host name to its address strings.
func (n *osNetwork) Lookup(ctx *Execution, name string, maxRecords Option[int64], timeout Option[Duration]) Result[*List[string], NetworkError] {
	if n.isClosed() {
		return netFail[*List[string]](errNetClosed)
	}
	max, ok := optLimit(maxRecords, netUnlimited)
	limit, valid := optTimeout(timeout)
	if !ok || !valid {
		return netFail[*List[string]](errNetInvalidInput)
	}
	local, cancel := timeoutContext(ctx.Context, netDurationOf(limit))
	defer cancel()
	call, finish, admitted := n.beginCall(local)
	if !admitted {
		return netFail[*List[string]](errNetClosed)
	}
	defer finish()
	if !n.policy.host(name) {
		return netFail[*List[string]](errNetDenied)
	}
	records, err := n.resolverInstance().LookupHost(call, name)
	CheckCancelled(ctx)
	if err != nil {
		if call.Err() != nil {
			if n.isClosed() {
				return netFail[*List[string]](errNetClosed)
			}
			return netFail[*List[string]](errNetTimeout)
		}
		return netFail[*List[string]](netFailed(err.Error()))
	}
	if int64(len(records)) > max {
		return netFail[*List[string]](errNetLimit)
	}
	return Ok[*List[string], NetworkError](NewList(records...))
}

// Resolve resolves the selected record category.
func (n *osNetwork) Resolve(ctx *Execution, name string, kind DnsKind, maxRecords Option[int64], timeout Option[Duration]) Result[*List[*DnsRecord], NetworkError] {
	max, ok := optLimit(maxRecords, netUnlimited)
	limit, valid := optTimeout(timeout)
	if !ok || !valid {
		return netFail[*List[*DnsRecord]](errNetInvalidInput)
	}
	if !n.policy.host(name) {
		return netFail[*List[*DnsRecord]](errNetDenied)
	}
	local, cancel := timeoutContext(ctx.Context, netDurationOf(limit))
	defer cancel()
	call, finish, admitted := n.beginCall(local)
	if !admitted {
		return netFail[*List[*DnsRecord]](errNetClosed)
	}
	defer finish()
	resolver := n.resolverInstance()
	out := []*DnsRecord{}
	add := func(value string, priority, weight, port int64) {
		out = append(out, &DnsRecord{Kind: kind, Value: value, Priority: priority, Weight: weight, Port: port})
	}
	var err error
	switch kind.(type) {
	case DnsKind_A, DnsKind_AAAA:
		family := "ip4"
		if _, v6 := kind.(DnsKind_AAAA); v6 {
			family = "ip6"
		}
		var ips []net.IP
		ips, err = resolver.LookupIP(call, family, name)
		for _, ip := range ips {
			add(ip.String(), 0, 0, 0)
		}
	case DnsKind_CNAME:
		var s string
		s, err = resolver.LookupCNAME(call, name)
		if err == nil {
			add(s, 0, 0, 0)
		}
	case DnsKind_MX:
		var records []*net.MX
		records, err = resolver.LookupMX(call, name)
		for _, v := range records {
			add(v.Host, int64(v.Pref), 0, 0)
		}
	case DnsKind_NS:
		var records []*net.NS
		records, err = resolver.LookupNS(call, name)
		for _, v := range records {
			add(v.Host, 0, 0, 0)
		}
	case DnsKind_TXT, DnsKind_PTR:
		var values []string
		if _, txt := kind.(DnsKind_TXT); txt {
			values, err = resolver.LookupTXT(call, name)
		} else {
			values, err = resolver.LookupAddr(call, name)
		}
		for _, v := range values {
			add(v, 0, 0, 0)
		}
	case DnsKind_SRV:
		var records []*net.SRV
		_, records, err = resolver.LookupSRV(call, "", "", name)
		for _, v := range records {
			add(v.Target, int64(v.Priority), int64(v.Weight), int64(v.Port))
		}
	default:
		return netFail[*List[*DnsRecord]](errNetInvalidInput)
	}
	if err != nil {
		return netFail[*List[*DnsRecord]](n.failure(ctx, call, err))
	}
	for _, record := range out {
		if !utf8.ValidString(record.Value) {
			return netFail[*List[*DnsRecord]](errNetInvalidData)
		}
	}
	if int64(len(out)) > max {
		return netFail[*List[*DnsRecord]](errNetLimit)
	}
	return Ok[*List[*DnsRecord], NetworkError](NewList(out...))
}
