package msruntime

import (
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"math/big"
	"reflect"
	"strings"
	"sync"
	"testing"
	"time"
)

// Loopback tests only: nothing here reaches an external network.

func testExec() *Execution { return RootExecution() }

// newTestNetwork returns a fresh unrestricted network closed with the test.
func newTestNetwork(t *testing.T) (*Execution, Network) {
	t.Helper()
	ctx := testExec()
	n := NewOSNetwork()
	t.Cleanup(func() { n.Close(ctx) })
	return ctx, n
}

func must[T, E any](t *testing.T, r Result[T, E]) T {
	t.Helper()
	if r.Failed {
		t.Fatalf("unexpected failure: %#v", r.Err)
	}
	return r.Val
}

// failedWith asserts a failed result whose error has the named Go type.
func failedWith[T, E any](t *testing.T, r Result[T, E], name string) E {
	t.Helper()
	if !r.Failed {
		t.Fatalf("expected %s, got success %#v", name, r.Val)
	}
	if got := reflect.TypeOf(r.Err).Name(); got != name {
		t.Fatalf("error = %s (%#v); want %s", got, r.Err, name)
	}
	return r.Err
}

func str(b *Bytes) string { return string(b.Data) }

func someBytes(t *testing.T, r Result[Option[*Bytes], IoError]) string {
	t.Helper()
	o := must(t, r)
	if !o.Some {
		t.Fatal("unexpected end of stream")
	}
	return str(o.Val)
}

func readAll(t *testing.T, ctx *Execution, read func(*Execution, Option[int64]) Result[Option[*Bytes], IoError], chunk int64) string {
	t.Helper()
	var out strings.Builder
	for {
		o := must(t, read(ctx, Some(chunk)))
		if !o.Some {
			return out.String()
		}
		out.Write(o.Val.Data)
	}
}

func headersOf(pairs ...string) *HttpHeaders {
	h := &HttpHeaders{}
	for i := 0; i+1 < len(pairs); i += 2 {
		h.add(pairs[i], NewBytes([]byte(pairs[i+1])))
	}
	return h
}

func headerValues(h *HttpHeaders, name string) []string {
	values, ok := h.lookup(name)
	if !ok {
		return nil
	}
	out := []string{}
	for _, v := range values.Items {
		out = append(out, string(v.Data))
	}
	return out
}

func get() HttpMethod  { return HttpMethod_Get{} }
func post() HttpMethod { return HttpMethod_Post{} }

func clientOptions() *HttpClientOptions {
	return &HttpClientOptions{MaxRedirects: Some(int64(4)), MaxIdleConnections: Some(int64(8)), MaxHeaderBytes: Some(int64(65536)), IdleTimeout: Some(Duration(time.Minute)), Decompress: true, Cookies: true, Tls: &TlsOptions{Alpn: NewList[string]()}}
}

func serverOptions() *HttpServerOptions {
	return &HttpServerOptions{MaxRequests: Some(int64(8)), MaxBodyBytes: Some(int64(1 << 20)), MaxResponseBytes: Some(int64(1 << 20)), MaxHeaderBytes: Some(int64(65536)), Timeout: Some(Duration(3 * time.Second)), Grace: Some(Duration(10 * time.Millisecond))}
}

func wsOptions(max int64, compression bool) *WebSocketOptions {
	return &WebSocketOptions{MaxMessageBytes: Some(max), Timeout: Some(Duration(time.Second)), Tls: &TlsOptions{}, Compression: compression}
}

// sliceStream is a ReadStream over a byte slice that records whether it was
// closed; borrowing it for an upload must not close it.
type sliceStream struct {
	mu     sync.Mutex
	data   []byte
	closed bool
}

func (s *sliceStream) Close(*Execution) Unit {
	s.mu.Lock()
	s.closed = true
	s.mu.Unlock()
	return Unit{}
}

func (s *sliceStream) Read(_ *Execution, maxBytes Option[int64]) Result[Option[*Bytes], IoError] {
	s.mu.Lock()
	defer s.mu.Unlock()
	if len(s.data) == 0 {
		return Ok[Option[*Bytes], IoError](None[*Bytes]())
	}
	n := len(s.data)
	if maxBytes.Some && int(maxBytes.Val) < n {
		n = int(maxBytes.Val)
	}
	part := append([]byte{}, s.data[:n]...)
	s.data = s.data[n:]
	return Ok[Option[*Bytes], IoError](Some(NewBytes(part)))
}

// pki issues certificates from one test CA.
type pki struct {
	t       *testing.T
	root    *x509.Certificate
	rootDER []byte
	key     ed25519.PrivateKey
	now     time.Time
}

func newPKI(t *testing.T) *pki {
	t.Helper()
	pub, key, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	now := time.Now()
	template := &x509.Certificate{SerialNumber: big.NewInt(1), Subject: pkix.Name{CommonName: "test CA"}, NotBefore: now.Add(-time.Minute), NotAfter: now.Add(time.Hour), IsCA: true, BasicConstraintsValid: true, KeyUsage: x509.KeyUsageCertSign}
	der, err := x509.CreateCertificate(rand.Reader, template, template, pub, key)
	if err != nil {
		t.Fatal(err)
	}
	root, err := x509.ParseCertificate(der)
	if err != nil {
		t.Fatal(err)
	}
	return &pki{t: t, root: root, rootDER: der, key: key, now: now}
}

func (p *pki) rootsPEM() string {
	return string(pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: p.rootDER}))
}

func (p *pki) issue(serial int64, name string, usage x509.ExtKeyUsage) (certPEM, keyPEM string) {
	p.t.Helper()
	pub, private, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		p.t.Fatal(err)
	}
	template := &x509.Certificate{SerialNumber: big.NewInt(serial), Subject: pkix.Name{CommonName: name}, DNSNames: []string{name}, NotBefore: p.now.Add(-time.Minute), NotAfter: p.now.Add(time.Hour), ExtKeyUsage: []x509.ExtKeyUsage{usage}, KeyUsage: x509.KeyUsageDigitalSignature}
	der, err := x509.CreateCertificate(rand.Reader, template, p.root, pub, p.key)
	if err != nil {
		p.t.Fatal(err)
	}
	pk, err := x509.MarshalPKCS8PrivateKey(private)
	if err != nil {
		p.t.Fatal(err)
	}
	return string(pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der})), string(pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: pk}))
}

// expectCancelled runs f and reports whether it unwound with the task
// cancellation panic.
func expectCancelled(f func()) (unwound bool) {
	defer func() {
		if r := recover(); r != nil {
			_, unwound = r.(cancelled)
			if !unwound {
				panic(r)
			}
		}
	}()
	f()
	return false
}

func netCancelledExec(ctx *Execution) (*Execution, context.CancelFunc) {
	c, cancel := context.WithCancel(ctx.Context)
	return netChild(ctx, c), cancel
}
