package msruntime

import (
	"bytes"
	"crypto/tls"
	"crypto/x509"
	"encoding/pem"
	"errors"
)

func init() {
	LibraryMethods = append(LibraryMethods, LibraryMethod{"Connection", "tls_info", libraryResult("TlsInfo"), nil})
	p := func(n, t string) LibraryParam { return LibraryParam{n, t} }
	libraryAdd("tls", "verify_certificates", libraryResult("Unit"), []LibraryParam{p("chain_pem", "String"), p("roots_pem", "String"), p("server_name", "String"), p("now", "Timestamp")}, func(_ *Execution, r string, a []Value) Value {
		if a[2].(string) == "" {
			return libraryError(r, "InvalidInput", "")
		}
		chain, err := libraryCertificates(a[0].(string))
		if err != nil || len(chain) == 0 {
			return libraryError(r, "InvalidData", "")
		}
		roots, err := libraryCertificates(a[1].(string))
		if err != nil || len(roots) == 0 {
			return libraryError(r, "InvalidData", "")
		}
		pool := x509.NewCertPool()
		for _, cert := range roots {
			pool.AddCert(cert)
		}
		intermediates := x509.NewCertPool()
		for _, cert := range chain[1:] {
			intermediates.AddCert(cert)
		}
		_, err = chain[0].Verify(x509.VerifyOptions{Roots: pool, Intermediates: intermediates, DNSName: a[2].(string), CurrentTime: a[3].(libraryTimestamp).t})
		if err != nil {
			return libraryError(r, "AuthenticationFailed", "")
		}
		return libraryOK(r, Unit{})
	})
}
func libraryCertificates(text string) ([]*x509.Certificate, error) {
	var out []*x509.Certificate
	data := []byte(text)
	for len(data) > 0 {
		data = bytes.TrimSpace(data)
		if len(data) == 0 {
			break
		}
		if !bytes.HasPrefix(data, []byte("-----BEGIN CERTIFICATE-----")) {
			return nil, errors.New("invalid certificate PEM")
		}
		block, rest := pem.Decode(data)
		if block == nil || block.Type != "CERTIFICATE" || len(block.Headers) != 0 {
			return nil, errors.New("invalid certificate PEM")
		}
		cert, err := x509.ParseCertificate(block.Bytes)
		if err != nil {
			return nil, err
		}
		out = append(out, cert)
		data = rest
	}
	return out, nil
}
func (c *libraryConnection) tlsInfo() Function {
	return libraryMethod("Connection", "tls_info", func(_ *Execution, r string, _ []Value) Value {
		conn, ok := c.conn.(*tls.Conn)
		if !ok {
			return libraryError(r, "InvalidInput", "")
		}
		state := conn.ConnectionState()
		certs := []Value{}
		for _, cert := range state.PeerCertificates {
			certs = append(certs, Bytes{append([]byte{}, cert.Raw...)})
		}
		return libraryOK(r, Record{"@std/TlsInfo", map[string]Value{"version": int64(state.Version), "cipher_suite": int64(state.CipherSuite), "alpn": state.NegotiatedProtocol, "peer_certificates": libraryList("@std/Bytes", certs), "verified": len(state.VerifiedChains) > 0}})
	})
}
