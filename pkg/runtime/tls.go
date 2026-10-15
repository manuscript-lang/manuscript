package msruntime

import (
	"bytes"
	"crypto/tls"
	"crypto/x509"
	"encoding/pem"
	"errors"
	"strings"
	"time"
)

func netTimestampOf(t time.Time) Timestamp {
	t = t.UTC()
	return Timestamp{Seconds: t.Unix(), Nanos: int32(t.Nanosecond())}
}

// Tls_ParseCertificates validates PEM certificates and exposes their metadata.
func Tls_ParseCertificates(_ *Execution, text string, maxCertificates Option[int64]) Result[*List[*CertificateInfo], TlsError] {
	max, ok := optLimit(maxCertificates, netUnlimited)
	if !ok {
		return Fail[*List[*CertificateInfo], TlsError](TlsError_InvalidInput{})
	}
	data := []byte(text)
	out := []*CertificateInfo{}
	for len(strings.TrimSpace(string(data))) > 0 {
		if !strings.HasPrefix(strings.TrimSpace(string(data)), "-----BEGIN CERTIFICATE-----") {
			return Fail[*List[*CertificateInfo], TlsError](TlsError_InvalidData{})
		}
		block, rest := pem.Decode(data)
		if block == nil || block.Type != "CERTIFICATE" || len(block.Headers) != 0 {
			return Fail[*List[*CertificateInfo], TlsError](TlsError_InvalidData{})
		}
		if int64(len(out)) >= max {
			return Fail[*List[*CertificateInfo], TlsError](TlsError_LimitExceeded{})
		}
		cert, err := x509.ParseCertificate(block.Bytes)
		if err != nil {
			return Fail[*List[*CertificateInfo], TlsError](TlsError_InvalidData{})
		}
		out = append(out, &CertificateInfo{Subject: cert.Subject.String(), Issuer: cert.Issuer.String(), DnsNames: NewList(append([]string{}, cert.DNSNames...)...), NotBefore: netTimestampOf(cert.NotBefore), NotAfter: netTimestampOf(cert.NotAfter), Der: NewBytes(append([]byte{}, block.Bytes...))})
		data = rest
	}
	return Ok[*List[*CertificateInfo], TlsError](NewList(out...))
}

// Tls_VerifyCertificates validates a chain against explicit roots, a name and
// a time, without any network or ambient trust.
func Tls_VerifyCertificates(_ *Execution, chainPem, rootsPem, serverName string, now Timestamp) Result[Unit, TlsError] {
	if serverName == "" {
		return Fail[Unit, TlsError](TlsError_InvalidInput{})
	}
	chain, err := parseCertificates(chainPem)
	if err != nil || len(chain) == 0 {
		return Fail[Unit, TlsError](TlsError_InvalidData{})
	}
	roots, err := parseCertificates(rootsPem)
	if err != nil || len(roots) == 0 {
		return Fail[Unit, TlsError](TlsError_InvalidData{})
	}
	pool := x509.NewCertPool()
	for _, cert := range roots {
		pool.AddCert(cert)
	}
	intermediates := x509.NewCertPool()
	for _, cert := range chain[1:] {
		intermediates.AddCert(cert)
	}
	_, err = chain[0].Verify(x509.VerifyOptions{Roots: pool, Intermediates: intermediates, DNSName: serverName, CurrentTime: time.Unix(now.Seconds, int64(now.Nanos)).UTC()})
	if err != nil {
		return Fail[Unit, TlsError](TlsError_AuthenticationFailed{})
	}
	return Ok[Unit, TlsError](Unit{})
}

func parseCertificates(text string) ([]*x509.Certificate, error) {
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

// tlsConfig builds a Go TLS configuration from explicit TlsOptions. Roots
// replace system trust; a server needs a certificate and key.
func tlsConfig(o *TlsOptions, server bool) (*tls.Config, error) {
	if o == nil {
		o = &TlsOptions{}
	}
	config := &tls.Config{MinVersion: tls.VersionTLS12, ServerName: o.ServerName, NextProtos: append([]string(nil), stringItems(o.Alpn)...)}
	for _, s := range config.NextProtos {
		if s == "" || len(s) > 255 {
			return nil, errors.New("invalid ALPN protocol")
		}
	}
	if o.RootsPem != "" {
		pool := x509.NewCertPool()
		certs, err := parseCertificates(o.RootsPem)
		if err != nil || len(certs) == 0 {
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
	if o.CertificatePem != "" || o.PrivateKeyPem != "" {
		cert, err := tls.X509KeyPair([]byte(o.CertificatePem), []byte(o.PrivateKeyPem))
		if err != nil {
			return nil, err
		}
		config.Certificates = []tls.Certificate{cert}
	}
	if server {
		if len(config.Certificates) == 0 {
			return nil, errors.New("server certificate required")
		}
		if o.RequireClientCertificate {
			config.ClientAuth = tls.RequireAndVerifyClientCert
		}
	} else if config.ServerName == "" || o.RequireClientCertificate {
		return nil, errors.New("invalid client TLS options")
	}
	return config, nil
}

// originTLSConfig is the client configuration of HTTP and WebSocket: each
// request validates its own hostname, never a fixed name from a prior origin.
func originTLSConfig(o *TlsOptions) (*tls.Config, error) {
	var c TlsOptions
	if o != nil {
		c = *o
	}
	c.ServerName = "origin.invalid"
	config, err := tlsConfig(&c, false)
	if config != nil {
		config.ServerName = ""
	}
	return config, err
}
