package msruntime

import (
	"crypto/x509"
	"encoding/pem"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestUrlParseFormatResolve(t *testing.T) {
	ctx := testExec()
	u := must(t, Url_Parse(ctx, "HTTPS://Example.COM:8443/a%2Fb/c?x=1&y=%20#frag"))
	if u.Scheme != "https" || u.Host != "example.com" || !u.Port.Some || u.Port.Val != 8443 || u.Path != "/a%2Fb/c" || u.Query != "x=1&y=%20" || u.Fragment != "frag" {
		t.Fatalf("%+v", u)
	}
	if got := must(t, Url_Format(ctx, u)); got != "https://example.com:8443/a%2Fb/c?x=1&y=%20#frag" {
		t.Fatal(got)
	}
	v6 := must(t, Url_Parse(ctx, "http://[::1]:80/"))
	if v6.Host != "::1" || v6.Port.Val != 80 {
		t.Fatalf("%+v", v6)
	}
	noPort := must(t, Url_Parse(ctx, "http://example.com/"))
	if noPort.Port.Some {
		t.Fatal("port should be none")
	}
	next := must(t, Url_Resolve(ctx, u, "../d?z=2"))
	if next.Path != "/d" || next.Query != "z=2" || next.Host != "example.com" {
		t.Fatalf("%+v", next)
	}
	for _, bad := range []string{"", "no-scheme", "http://user:pw@host/", "http://host:99999/", "mailto:a@b"} {
		failedWith(t, Url_Parse(ctx, bad), "UrlError_InvalidData")
	}
	failedWith(t, Url_Format(ctx, &Url{Scheme: "http", Host: "h", Port: Some(int(70000))}), "UrlError_InvalidInput")
	failedWith(t, Url_Format(ctx, &Url{Scheme: "http", Host: "h", Query: "a b"}), "UrlError_InvalidInput")
	failedWith(t, Url_Resolve(ctx, &Url{Scheme: "http", Host: "h bad"}, "/x"), "UrlError_InvalidInput")
}

func TestUrlComponentsAndQuery(t *testing.T) {
	ctx := testExec()
	if got := Url_EncodeComponent(ctx, "a b/é~"); got != "a%20b%2F%C3%A9~" {
		t.Fatal(got)
	}
	if got := must(t, Url_DecodeComponent(ctx, "a%20b+c")); got != "a b+c" {
		t.Fatal(got)
	}
	failedWith(t, Url_DecodeComponent(ctx, "%zz"), "UrlError_InvalidData")
	failedWith(t, Url_DecodeComponent(ctx, "%ff"), "UrlError_InvalidData")
	q := must(t, Url_ParseQuery(ctx, "a=1&a=2&b&c=x+y%21&&", None[int]()))
	var got []string
	for _, e := range q.Items {
		got = append(got, e.Key+"="+e.Value)
	}
	if strings.Join(got, ",") != "a=1,a=2,b=,c=x y!" {
		t.Fatal(got)
	}
	failedWith(t, Url_ParseQuery(ctx, "a=1", Some(int(0))), "UrlError_LimitExceeded")
	failedWith(t, Url_ParseQuery(ctx, "a=1", Some(int(-1))), "UrlError_InvalidInput")
	failedWith(t, Url_ParseQuery(ctx, "a=%zz", None[int]()), "UrlError_InvalidData")
	if got := Url_FormatQuery(ctx, q); got != "a=1&a=2&b=&c=x+y%21" {
		t.Fatal(got)
	}
	for e, want := range map[UrlError]string{UrlError_InvalidInput{}: "URL: invalid input", UrlError_InvalidData{}: "URL: invalid data", UrlError_LimitExceeded{}: "URL: limit exceeded"} {
		if got := Errors_Message_UrlError(ctx, e); got != want {
			t.Fatal(got, want)
		}
	}
}

func TestTlsCertificateHelpers(t *testing.T) {
	ctx := testExec()
	ca := newPKI(t)
	cert, _ := ca.issue(2, "service.test", x509.ExtKeyUsageServerAuth)
	roots := ca.rootsPEM()
	infos := must(t, Tls_ParseCertificates(ctx, cert+roots, Some(int(2))))
	if len(infos.Items) != 2 || infos.Items[0].DnsNames.Items[0] != "service.test" || len(infos.Items[0].Der.Data) == 0 {
		t.Fatalf("%+v", infos.Items[0])
	}
	notAfter := time.Unix(infos.Items[0].NotAfter.Seconds, int64(infos.Items[0].NotAfter.Nanos))
	if !notAfter.After(time.Now()) {
		t.Fatal("not_after", notAfter)
	}
	failedWith(t, Tls_ParseCertificates(ctx, cert+roots, Some(int(1))), "TlsError_LimitExceeded")
	failedWith(t, Tls_ParseCertificates(ctx, cert, Some(int(-1))), "TlsError_InvalidInput")
	failedWith(t, Tls_ParseCertificates(ctx, "invalid PEM", None[int]()), "TlsError_InvalidData")
	failedWith(t, Tls_ParseCertificates(ctx, "-----BEGIN CERTIFICATE-----\nAAAA\n-----END CERTIFICATE-----\n", None[int]()), "TlsError_InvalidData")
	if got := must(t, Tls_ParseCertificates(ctx, "  \n", None[int]())); len(got.Items) != 0 {
		t.Fatal("blank input")
	}
	now := netTimestampOf(time.Now())
	must(t, Tls_VerifyCertificates(ctx, cert, roots, "service.test", now))
	failedWith(t, Tls_VerifyCertificates(ctx, cert, roots, "other.test", now), "TlsError_AuthenticationFailed")
	failedWith(t, Tls_VerifyCertificates(ctx, cert, roots, "service.test", netTimestampOf(time.Now().Add(24*time.Hour))), "TlsError_AuthenticationFailed")
	failedWith(t, Tls_VerifyCertificates(ctx, cert, roots, "", now), "TlsError_InvalidInput")
	failedWith(t, Tls_VerifyCertificates(ctx, "", roots, "service.test", now), "TlsError_InvalidData")
	failedWith(t, Tls_VerifyCertificates(ctx, cert, "", "service.test", now), "TlsError_InvalidData")
	for e, want := range map[TlsError]string{TlsError_InvalidInput{}: "TLS: invalid input", TlsError_AuthenticationFailed{}: "TLS: authentication failed", TlsError_InvalidData{}: "TLS: invalid data", TlsError_LimitExceeded{}: "TLS: limit exceeded"} {
		if got := Errors_Message_TlsError(ctx, e); got != want {
			t.Fatal(got, want)
		}
	}
}

func TestTlsVerifiedConnectionAndHTTP2(t *testing.T) {
	server := httptest.NewUnstartedServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { io.WriteString(w, r.Proto) }))
	server.EnableHTTP2 = true
	server.StartTLS()
	defer server.Close()
	roots := string(pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: server.Certificate().Raw}))
	ctx, n := newTestNetwork(t)
	options := clientOptions()
	options.Tls = &TlsOptions{RootsPem: roots}
	client := must(t, n.HttpClient(ctx, options))
	body := must(t, client.Request(ctx, get(), server.URL, headersOf(), NewBytes(nil), Some(int(100)), Some(Duration(time.Second))))
	if got := someBytes(t, body.Read(ctx, Some(int(100)))); got != "HTTP/2.0" {
		t.Fatal(got)
	}
	body.Close(ctx)
	// Without the roots the certificate is not trusted: there is no insecure mode.
	untrusted := must(t, n.HttpClient(ctx, clientOptions()))
	failedWith(t, untrusted.Request(ctx, get(), server.URL, headersOf(), NewBytes(nil), Some(int(100)), Some(Duration(time.Second))), "HttpError_Failed")
	conn := must(t, n.ConnectTlsConfig(ctx, server.Listener.Addr().String(), &TlsOptions{ServerName: "example.com", RootsPem: roots}, Some(Duration(time.Second))))
	info := must(t, conn.TlsInfo(ctx))
	if !info.Verified || info.Version < 0x0303 || len(info.PeerCertificates.Items) == 0 {
		t.Fatalf("%+v", info)
	}
	failedWith(t, n.ConnectTlsConfig(ctx, server.Listener.Addr().String(), &TlsOptions{ServerName: "wrong.invalid", RootsPem: roots}, Some(Duration(time.Second))), "NetworkError_Failed")
	failedWith(t, n.ConnectTlsConfig(ctx, server.Listener.Addr().String(), &TlsOptions{}, Some(Duration(time.Second))), "NetworkError_InvalidInput")
	failedWith(t, n.ConnectTlsConfig(ctx, server.Listener.Addr().String(), &TlsOptions{ServerName: "example.com", RootsPem: "junk"}, Some(Duration(time.Second))), "NetworkError_InvalidInput")
	failedWith(t, n.ConnectTlsConfig(ctx, server.Listener.Addr().String(), &TlsOptions{ServerName: "example.com", RootsPem: roots, Alpn: NewList("")}, Some(Duration(time.Second))), "NetworkError_InvalidInput")
	// A plain connection has no TLS information.
	plain := must(t, n.Listen(ctx, "127.0.0.1:0"))
	pc := must(t, n.Connect(ctx, plain.Address(ctx), None[Duration]()))
	failedWith(t, pc.TlsInfo(ctx), "TlsError_InvalidInput")
}

func TestTlsMutualListener(t *testing.T) {
	ca := newPKI(t)
	cert, key := ca.issue(2, "service.test", x509.ExtKeyUsageServerAuth)
	clientCert, clientKey := ca.issue(3, "client.test", x509.ExtKeyUsageClientAuth)
	roots := ca.rootsPEM()
	ctx, n := newTestNetwork(t)
	failedWith(t, n.ListenTls(ctx, "127.0.0.1:0", &TlsOptions{}, None[Duration]()), "NetworkError_InvalidInput")
	listener := must(t, n.ListenTls(ctx, "127.0.0.1:0", &TlsOptions{CertificatePem: cert, PrivateKeyPem: key, RootsPem: roots, RequireClientCertificate: true}, Some(Duration(time.Second))))
	address := listener.Address(ctx)
	accepted := make(chan Result[Connection, NetworkError], 1)
	go func() { accepted <- listener.Accept(ctx, Some(Duration(time.Second))) }()
	client := must(t, n.ConnectTlsConfig(ctx, address, &TlsOptions{ServerName: "service.test", RootsPem: roots, CertificatePem: clientCert, PrivateKeyPem: clientKey}, Some(Duration(time.Second))))
	server := must(t, <-accepted)
	must(t, client.Write(ctx, NewBytes([]byte("verified")), None[Duration]()))
	if got := someBytes(t, server.Read(ctx, Some(int(20)), Some(Duration(time.Second)))); got != "verified" {
		t.Fatal(got)
	}
	// TLS connections half-close like TCP.
	must(t, client.ShutdownWrite(ctx))
	if o := must(t, server.Read(ctx, Some(int(1)), Some(Duration(time.Second)))); o.Some {
		t.Fatal("expected EOF")
	}
	// A client without a certificate fails the handshake and the listener survives.
	go func() { accepted <- listener.Accept(ctx, Some(Duration(time.Second))) }()
	anonymous := n.ConnectTlsConfig(ctx, address, &TlsOptions{ServerName: "service.test", RootsPem: roots}, Some(Duration(time.Second)))
	if !anonymous.Failed {
		// TLS 1.3 reports the missing client certificate on first use.
		anonymous.Val.Write(ctx, NewBytes([]byte("x")), None[Duration]())
		anonymous.Val.Read(ctx, Some(int(1)), Some(Duration(time.Second)))
	}
	failedWith(t, <-accepted, "NetworkError_Failed")
}
