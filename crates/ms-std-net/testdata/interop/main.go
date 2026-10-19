// Interop peer for ms-std-net: a Go net/http server and client, over plain HTTP/1.1
// and TLS (HTTP/1.1 or HTTP/2), driven by tests/go_interop.rs.
package main

import (
	"crypto/tls"
	"crypto/x509"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/gorilla/websocket"
)

func pattern(n int) []byte {
	b := make([]byte, n)
	for i := range b {
		b[i] = byte('a' + i%26)
	}
	return b
}

func serve(mode, addr, cert, key string) {
	mux := http.NewServeMux()
	mux.HandleFunc("/proto", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprint(w, r.Proto)
	})
	mux.HandleFunc("/echo", func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		w.Header().Set("X-Seen-Method", r.Method)
		w.Header().Set("X-Seen-Agent", r.Header.Get("User-Agent"))
		w.Write(body)
	})
	mux.HandleFunc("/big", func(w http.ResponseWriter, r *http.Request) {
		w.Write(pattern(1 << 20))
	})
	mux.HandleFunc("/redirect", func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, "/proto", http.StatusFound)
	})
	mux.HandleFunc("/cookie", func(w http.ResponseWriter, r *http.Request) {
		http.SetCookie(w, &http.Cookie{Name: "k", Value: "v", Path: "/"})
		fmt.Fprint(w, r.Header.Get("Cookie"))
	})
	mux.HandleFunc("/trailer", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Trailer", "X-Tail")
		fmt.Fprint(w, "body")
		w.Header().Set("X-Tail", "t")
	})
	mux.HandleFunc("/stream", func(w http.ResponseWriter, r *http.Request) {
		f := w.(http.Flusher)
		for i := 0; i < 5; i++ {
			fmt.Fprintf(w, "chunk%d;", i)
			f.Flush()
			time.Sleep(10 * time.Millisecond)
		}
	})
	up := websocket.Upgrader{Subprotocols: []string{"chat"}, CheckOrigin: func(*http.Request) bool { return true }}
	mux.HandleFunc("/ws", func(w http.ResponseWriter, r *http.Request) {
		c, err := up.Upgrade(w, r, nil)
		if err != nil {
			return
		}
		defer c.Close()
		for {
			kind, data, err := c.ReadMessage()
			if err != nil {
				return
			}
			c.WriteMessage(kind, append([]byte(c.Subprotocol()+":"), data...))
		}
	})
	srv := &http.Server{Addr: addr, Handler: mux}
	ln, err := net.Listen("tcp", addr)
	if err != nil {
		fmt.Println("listen:", err)
		os.Exit(2)
	}
	fmt.Println("ready", ln.Addr())
	switch mode {
	case "h1":
		srv.Serve(ln)
	case "tls-h1":
		srv.TLSConfig = &tls.Config{NextProtos: []string{"http/1.1"}}
		srv.TLSNextProto = map[string]func(*http.Server, *tls.Conn, http.Handler){}
		srv.ServeTLS(ln, cert, key)
	default:
		srv.ServeTLS(ln, cert, key)
	}
}

func get(c *http.Client, method, url, body string) {
	var rd io.Reader
	if body != "" {
		rd = strings.NewReader(body)
	}
	req, _ := http.NewRequest(method, url, rd)
	resp, err := c.Do(req)
	if err != nil {
		fmt.Printf("%s %s ERR %v\n", method, url, err)
		return
	}
	data, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	fmt.Printf("%s %s %d %s len=%d body=%.40q agent=%s\n", method, url, resp.StatusCode, resp.Proto, len(data), data, resp.Header.Get("X-Seen-Agent"))
}

// client requests the endpoints of the ms-std-net server under test.
func client(mode, base, cert string) {
	tr := &http.Transport{}
	if mode != "h1" {
		pool := x509.NewCertPool()
		pem, _ := os.ReadFile(cert)
		pool.AppendCertsFromPEM(pem)
		tr.TLSClientConfig = &tls.Config{RootCAs: pool}
		tr.ForceAttemptHTTP2 = mode == "tls-h2"
		if mode == "tls-h1" {
			tr.TLSClientConfig.NextProtos = []string{"http/1.1"}
		}
	}
	c := &http.Client{Transport: tr, Timeout: 10 * time.Second}
	get(c, "GET", base+"/proto", "")
	get(c, "POST", base+"/echo", strings.Repeat("x", 200000))
	get(c, "GET", base+"/big", "")
	get(c, "GET", base+"/redirect", "")
	get(c, "HEAD", base+"/proto", "")
	get(c, "GET", base+"/missing", "")
}

// wsClient dials the ms-std-net server, exchanges a text and a binary message
// and reports what it saw.
func wsClient(base, cert string) {
	d := websocket.Dialer{Subprotocols: []string{"other", "chat"}, HandshakeTimeout: 5 * time.Second}
	if strings.HasPrefix(base, "wss") {
		pool := x509.NewCertPool()
		pem, _ := os.ReadFile(cert)
		pool.AppendCertsFromPEM(pem)
		d.TLSClientConfig = &tls.Config{RootCAs: pool, NextProtos: []string{"http/1.1"}}
	}
	c, resp, err := d.Dial(base+"/ws", nil)
	if err != nil {
		fmt.Println("dial ERR", err)
		return
	}
	fmt.Println("dial", resp.StatusCode, c.Subprotocol())
	c.WriteMessage(websocket.TextMessage, []byte("hello"))
	c.WriteMessage(websocket.BinaryMessage, []byte{1, 2, 3})
	c.WriteMessage(websocket.TextMessage, []byte(strings.Repeat("z", 100000)))
	for i := 0; i < 3; i++ {
		kind, data, err := c.ReadMessage()
		if err != nil {
			fmt.Println("read ERR", err)
			return
		}
		fmt.Printf("msg kind=%d len=%d head=%.12q\n", kind, len(data), data)
	}
	c.WriteControl(websocket.CloseMessage, websocket.FormatCloseMessage(websocket.CloseNormalClosure, "bye"), time.Now().Add(time.Second))
	_, _, err = c.ReadMessage()
	fmt.Println("after close:", err)
}

func main() {
	switch os.Args[1] {
	case "server":
		serve(os.Args[2], os.Args[3], os.Args[4], os.Args[5])
	case "ws-client":
		wsClient(os.Args[2], os.Args[3])
	case "client":
		client(os.Args[2], os.Args[3], os.Args[4])
	}
}
