// Holds idle connections open against the server in ../server and reports how many held.
//
//	client ws  <port> <n>   WebSocket upgrade on /ws, then hold
//	client tls <port> <n>   TLS handshake and one GET /health, then hold
//
// It prints "holding <k>" and then sleeps until killed; the script reads the server's memory.
package main

import (
	"bufio"
	"crypto/tls"
	"fmt"
	"net"
	"os"
	"strconv"
	"strings"
	"time"
)

func main() {
	if len(os.Args) != 4 {
		fmt.Fprintln(os.Stderr, "usage: client ws|tls <port> <n>")
		os.Exit(2)
	}
	n, _ := strconv.Atoi(os.Args[3])
	addr := "127.0.0.1:" + os.Args[2]
	var held []net.Conn
	for i := 0; i < n; i++ {
		var c net.Conn
		var err error
		if os.Args[1] == "tls" {
			c, err = tls.Dial("tcp", addr, &tls.Config{InsecureSkipVerify: true, MaxVersion: tls.VersionTLS13})
		} else {
			c, err = net.Dial("tcp", addr)
		}
		if err != nil {
			fmt.Println("dial error after", i, err)
			break
		}
		path, extra := "/health", ""
		if os.Args[1] == "ws" {
			path = "/ws"
			extra = "Upgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n"
		}
		fmt.Fprintf(c, "GET %s HTTP/1.1\r\nHost: x\r\n%s\r\n", path, extra)
		r := bufio.NewReader(c)
		line, err := r.ReadString('\n')
		want := "HTTP/1.1 200"
		if os.Args[1] == "ws" {
			want = "HTTP/1.1 101"
		}
		if err != nil || !strings.HasPrefix(line, want) {
			fmt.Println("bad response after", i, err, line)
			break
		}
		for { // headers, then (tls) the 3-byte body stays unread in the buffer
			h, err := r.ReadString('\n')
			if err != nil || h == "\r\n" {
				break
			}
		}
		held = append(held, c)
	}
	fmt.Println("holding", len(held))
	time.Sleep(time.Hour)
}
