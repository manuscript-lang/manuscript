//go:build !ms_lean

package msruntime

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"encoding/pem"
	"errors"
	"net"
	"net/netip"
	"os"
	"strings"
	"time"
	"unicode/utf8"
)

func init() {
	LibraryMethods = append(LibraryMethods, []LibraryMethod{
		{"Network", "restrict", libraryResult("Network", "NetworkError"), []LibraryParam{{"hosts", "List[String]"}, {"cidrs", "List[String]"}, {"allow_listen", "Bool"}}},
		{"Network", "with_resolver", libraryResult("Network", "NetworkError"), []LibraryParam{{"address", "String"}}},
		{"Network", "resolve", libraryResult("List[DnsRecord]", "NetworkError"), []LibraryParam{{"name", "String"}, {"kind", "String"}, {"max_records", "Optional[Int]"}, {"timeout", "Optional[Duration]"}}},
		{"Network", "connect_unix", libraryResult("Connection", "NetworkError"), []LibraryParam{{"path", "String"}, {"timeout", "Optional[Duration]"}}},
		{"Network", "listen_unix", libraryResult("Listener", "NetworkError"), []LibraryParam{{"path", "String"}}},
		{"Network", "connect_tls_config", libraryResult("Connection", "NetworkError"), []LibraryParam{{"address", "String"}, {"options", "TlsOptions"}, {"timeout", "Optional[Duration]"}}},
		{"Network", "listen_tls", libraryResult("Listener", "NetworkError"), []LibraryParam{{"address", "String"}, {"options", "TlsOptions"}, {"handshake_timeout", "Optional[Duration]"}}},
	}...)
	p := func(n, t string) LibraryParam { return LibraryParam{n, t} }
	libraryAdd("tls", "parse_certificates", libraryResult("List[CertificateInfo]", "TlsError"), []LibraryParam{p("pem", "String"), p("max_certificates", "Optional[Int]")}, func(_ *Execution, r string, a []Value) Value {
		data := []byte(a[0].(string))
		max := nativeInteger(a[1])
		if max < 0 {
			return libraryError(r, "InvalidInput", "")
		}
		var out []Value
		for len(strings.TrimSpace(string(data))) > 0 {
			if !strings.HasPrefix(strings.TrimSpace(string(data)), "-----BEGIN CERTIFICATE-----") {
				return libraryError(r, "InvalidData", "")
			}
			block, rest := pem.Decode(data)
			if block == nil || block.Type != "CERTIFICATE" || len(block.Headers) != 0 {
				return libraryError(r, "InvalidData", "")
			}
			if int64(len(out)) >= max {
				return libraryError(r, "LimitExceeded", "")
			}
			cert, err := x509.ParseCertificate(block.Bytes)
			if err != nil {
				return libraryError(r, "InvalidData", "")
			}
			out = append(out, Record{"@std/CertificateInfo", map[string]Value{"subject": cert.Subject.String(), "issuer": cert.Issuer.String(), "dns_names": libraryStrings(cert.DNSNames), "not_before": libraryTimestamp{cert.NotBefore.UTC()}, "not_after": libraryTimestamp{cert.NotAfter.UTC()}, "der": Bytes{append([]byte{}, block.Bytes...)}}})
			data = rest
		}
		return libraryOK(r, libraryList("@std/CertificateInfo", out))
	})
	libraryAdd("net", "parse_cidr", libraryResult("String", "NetworkError"), []LibraryParam{p("text", "String")}, func(_ *Execution, r string, a []Value) Value {
		prefix, err := netip.ParsePrefix(a[0].(string))
		if err != nil {
			return libraryError(r, "InvalidData", "")
		}
		return libraryOK(r, prefix.Masked().String())
	})
	libraryAdd("net", "contains_ip", libraryResult("Bool", "NetworkError"), []LibraryParam{p("cidr", "String"), p("address", "String")}, func(_ *Execution, r string, a []Value) Value {
		prefix, e1 := netip.ParsePrefix(a[0].(string))
		ip, e2 := netip.ParseAddr(a[1].(string))
		if e1 != nil || e2 != nil {
			return libraryError(r, "InvalidData", "")
		}
		return libraryOK(r, prefix.Contains(ip))
	})
}

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
func (n *network) resolverInstance() *net.Resolver {
	if n.resolver != nil {
		return n.resolver
	}
	return net.DefaultResolver
}
func (n *network) dial(ctx context.Context, kind, address string) (net.Conn, error) {
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
func (n *network) listenAllowed(address string) bool {
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
func (n *network) own(v Value) bool {
	n.mu.Lock()
	defer n.mu.Unlock()
	if n.closed {
		return false
	}
	n.resources = append(n.resources, v)
	return true
}
func (n *network) networkFailure(ctx *Execution, r string, call context.Context, err error) Value {
	CheckCancelled(ctx)
	if n.isClosed() {
		return libraryError(r, "Closed", "")
	}
	if call != nil && call.Err() != nil {
		return libraryError(r, "Timeout", "")
	}
	if errors.Is(err, os.ErrPermission) {
		return libraryError(r, "PermissionDenied", "")
	}
	if errors.Is(err, net.ErrClosed) {
		return libraryError(r, "Closed", "")
	}
	if e, ok := err.(net.Error); ok && e.Timeout() {
		return libraryError(r, "Timeout", "")
	}
	return libraryError(r, "Failed", err.Error())
}
func libraryTLSOptions(value Value, server bool) (*tls.Config, error) {
	f := value.(Record).Fields
	config := &tls.Config{MinVersion: tls.VersionTLS12, ServerName: f["server_name"].(string), NextProtos: libraryStringValues(f["alpn"])}
	for _, s := range config.NextProtos {
		if s == "" || len(s) > 255 {
			return nil, errors.New("invalid ALPN protocol")
		}
	}
	roots := f["roots_pem"].(string)
	certPEM, keyPEM := f["certificate_pem"].(string), f["private_key_pem"].(string)
	if roots != "" {
		pool := x509.NewCertPool()
		certs, parseError := libraryCertificates(roots)
		if parseError != nil || len(certs) == 0 {
			return nil, errors.New("invalid trust roots")
		}
		for _, cert := range certs {
			pool.AddCert(cert)
		}
		if server {
			config.ClientCAs = pool
		} else {
			config.RootCAs = pool
		}
	}
	if certPEM != "" || keyPEM != "" {
		cert, err := tls.X509KeyPair([]byte(certPEM), []byte(keyPEM))
		if err != nil {
			return nil, err
		}
		config.Certificates = []tls.Certificate{cert}
	}
	if server {
		if len(config.Certificates) == 0 {
			return nil, errors.New("server certificate required")
		}
		if f["require_client_certificate"].(bool) {
			config.ClientAuth = tls.RequireAndVerifyClientCert
		}
	} else {
		if config.ServerName == "" || f["require_client_certificate"].(bool) {
			return nil, errors.New("invalid client TLS options")
		}
	}
	return config, nil
}
func (n *network) extendedOperation(name string) (Function, bool) {
	switch name {
	case "restrict", "with_resolver":
		return libraryAcquisition("Network", name, func(ctx *Execution, r string, a []Value) Value {
			child := &network{policy: n.policy, resolver: n.resolver, parent: n}
			if name == "restrict" {
				p := &networkPolicy{hosts: map[string]bool{}, listen: a[2].(bool), parent: n.policy}
				for _, host := range libraryStringValues(a[0]) {
					if host == "" || strings.ContainsAny(host, "/\\\x00 :") {
						return libraryError(r, "InvalidInput", "")
					}
					p.hosts[strings.ToLower(strings.TrimSuffix(host, "."))] = true
				}
				for _, text := range libraryStringValues(a[1]) {
					prefix, err := netip.ParsePrefix(text)
					if err != nil {
						return libraryError(r, "InvalidInput", "")
					}
					p.prefixes = append(p.prefixes, prefix.Masked())
				}
				child.policy = p
			} else {
				address := a[0].(string)
				host, _, err := net.SplitHostPort(address)
				ip, e := netip.ParseAddr(host)
				if err != nil || e != nil {
					return libraryError(r, "InvalidInput", "")
				}
				if !n.policy.host(host) || !n.policy.ip(ip) {
					return libraryError(r, "PermissionDenied", "")
				}
				child.resolver = &net.Resolver{PreferGo: true, Dial: func(ctx context.Context, kind, _ string) (net.Conn, error) {
					return (&net.Dialer{}).DialContext(ctx, kind, address)
				}}
			}
			if !n.own(child) {
				return libraryError(r, "Closed", "")
			}
			return libraryOK(r, ViewOf("@std/Network", child))
		}), true
	case "resolve":
		return libraryMethod("Network", name, func(ctx *Execution, r string, a []Value) Value { return n.resolve(ctx, r, a) }), true
	case "connect_unix", "listen_unix", "connect_tls_config", "listen_tls":
		return libraryAcquisition("Network", name, func(ctx *Execution, r string, a []Value) Value {
			address := a[0].(string)
			timeout := Duration(30 * time.Second)
			if name == "connect_unix" || name == "connect_tls_config" || name == "listen_tls" {
				timeout = a[len(a)-1].(Duration)
				if timeout < nativeNoTimeout {
					return libraryError(r, "InvalidInput", "")
				}
			}
			local, cancel := contextWithLibraryTimeout(ctx, timeout)
			defer cancel()
			call, finish, ok := n.beginCall(local)
			if !ok {
				return libraryError(r, "Closed", "")
			}
			defer finish()
			if name == "connect_unix" || name == "connect_tls_config" {
				kind := "tcp"
				if name == "connect_unix" {
					kind = "unix"
				}
				conn, err := n.dial(call, kind, address)
				if err != nil {
					return n.networkFailure(ctx, r, call, err)
				}
				if name == "connect_tls_config" {
					config, err := libraryTLSOptions(a[1], false)
					if err != nil {
						conn.Close()
						return libraryError(r, "InvalidInput", "")
					}
					secure := tls.Client(conn, config)
					if err := secure.HandshakeContext(call); err != nil {
						conn.Close()
						return n.networkFailure(ctx, r, call, err)
					}
					conn = secure
				}
				resource := newLibraryConnection(conn)
				resource.owner = n
				if !n.own(resource) {
					resource.close()
					return libraryError(r, "Closed", "")
				}
				return libraryOK(r, ViewOf("@std/Connection", resource))
			}
			kind := "tcp"
			if name == "listen_unix" {
				kind = "unix"
				if n.policy != nil {
					return libraryError(r, "PermissionDenied", "")
				}
			} else if !n.listenAllowed(address) {
				return libraryError(r, "PermissionDenied", "")
			}
			listener, err := (&net.ListenConfig{}).Listen(call, kind, address)
			if err != nil {
				return n.networkFailure(ctx, r, call, err)
			}
			resource := &libraryListener{listener: listener, owner: n, gate: make(chan struct{}, 1), released: make(chan struct{})}
			resource.gate <- struct{}{}
			if name == "listen_tls" {
				config, err := libraryTLSOptions(a[1], true)
				if err != nil {
					listener.Close()
					return libraryError(r, "InvalidInput", "")
				}
				resource.tlsConfig = config
				resource.handshakeTimeout = time.Duration(timeout)
			}
			if !n.own(resource) {
				listener.Close()
				return libraryError(r, "Closed", "")
			}
			return libraryOK(r, ViewOf("@std/Listener", resource))
		}), true
	}
	return Function{}, false
}
func (n *network) resolve(ctx *Execution, r string, a []Value) Value {
	name, kind := a[0].(string), strings.ToUpper(a[1].(string))
	max, timeout := nativeInteger(a[2]), a[3].(Duration)
	if max < 0 || timeout < nativeNoTimeout {
		return libraryError(r, "InvalidInput", "")
	}
	if !n.policy.host(name) {
		return libraryError(r, "PermissionDenied", "")
	}
	local, cancel := contextWithLibraryTimeout(ctx, timeout)
	defer cancel()
	call, finish, ok := n.beginCall(local)
	if !ok {
		return libraryError(r, "Closed", "")
	}
	defer finish()
	resolver := n.resolverInstance()
	var out []Value
	add := func(value string, priority, weight, port int64) {
		out = append(out, Record{"@std/DnsRecord", map[string]Value{"kind": kind, "value": value, "priority": defaultInteger(priority), "weight": defaultInteger(weight), "port": defaultInteger(port)}})
	}
	var err error
	switch kind {
	case "A", "AAAA":
		family := "ip4"
		if kind == "AAAA" {
			family = "ip6"
		}
		var ips []net.IP
		ips, err = resolver.LookupIP(call, family, name)
		for _, ip := range ips {
			add(ip.String(), 0, 0, 0)
		}
	case "CNAME":
		var s string
		s, err = resolver.LookupCNAME(call, name)
		if err == nil {
			add(s, 0, 0, 0)
		}
	case "MX":
		var records []*net.MX
		records, err = resolver.LookupMX(call, name)
		for _, v := range records {
			add(v.Host, int64(v.Pref), 0, 0)
		}
	case "NS":
		var records []*net.NS
		records, err = resolver.LookupNS(call, name)
		for _, v := range records {
			add(v.Host, 0, 0, 0)
		}
	case "TXT", "PTR":
		var values []string
		if kind == "TXT" {
			values, err = resolver.LookupTXT(call, name)
		} else {
			values, err = resolver.LookupAddr(call, name)
		}
		for _, v := range values {
			add(v, 0, 0, 0)
		}
	case "SRV":
		var records []*net.SRV
		_, records, err = resolver.LookupSRV(call, "", "", name)
		for _, v := range records {
			add(v.Target, int64(v.Priority), int64(v.Weight), int64(v.Port))
		}
	default:
		return libraryError(r, "InvalidInput", "")
	}
	if err != nil {
		return n.networkFailure(ctx, r, call, err)
	}
	for _, record := range out {
		if !utf8.ValidString(record.(Record).Fields["value"].(string)) {
			return libraryError(r, "InvalidData", "")
		}
	}
	if int64(len(out)) > max {
		return libraryError(r, "LimitExceeded", "")
	}
	return libraryOK(r, libraryList("@std/DnsRecord", out))
}
