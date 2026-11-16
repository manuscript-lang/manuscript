// Open-loop load generator: sends requests on a fixed schedule over keep-alive
// connections and measures latency from the scheduled send time, so a stall is
// charged to every request it delayed (no coordinated omission).
package main

import (
	"bufio"
	"crypto/tls"
	"flag"
	"fmt"
	"io"
	"net"
	"net/http"
	"sort"
	"sync"
	"time"
)

func main() {
	addr := flag.String("addr", "127.0.0.1:8080", "")
	rate := flag.Int("rate", 4000, "requests per second; 0 sends back to back (closed loop) and reports throughput")
	bigEvery := flag.Int("big", 0, "every Nth request per connection is /big (excluded from stats)")
	slowEvery := flag.Int("slow", 0, "every Nth request per connection is /slow (excluded from stats)")
	conns := flag.Int("conns", 64, "connections")
	dur := flag.Duration("dur", 20*time.Second, "")
	warm := flag.Duration("warm", 3*time.Second, "")
	useTLS := flag.Bool("tls", false, "HTTP/1.1 over TLS (certificate not verified)")
	useH2 := flag.Bool("h2", false, "HTTP/2 over TLS: one connection each, certificate not verified")
	flag.Parse()

	per := time.Duration(0)
	if *rate > 0 {
		per = time.Second * time.Duration(*conns) / time.Duration(*rate)
	}
	var mu sync.Mutex
	var lats []time.Duration
	var errs int
	start := time.Now().Add(200 * time.Millisecond)
	end := start.Add(*warm + *dur)
	if *rate == 0 {
		per = time.Nanosecond
	}
	var wg sync.WaitGroup
	for c := 0; c < *conns; c++ {
		wg.Add(1)
		go func(c int) {
			defer wg.Done()
			var conn net.Conn
			var err error
			var h2 *http.Client
			switch {
			case *useH2:
				// One transport per connection: HTTP/2 multiplexes, so this keeps `conns` sockets.
				h2 = &http.Client{Transport: &http.Transport{
					TLSClientConfig:   &tls.Config{InsecureSkipVerify: true, NextProtos: []string{"h2"}},
					ForceAttemptHTTP2: true,
					MaxConnsPerHost:   1,
				}}
			case *useTLS:
				conn, err = tls.Dial("tcp", *addr, &tls.Config{InsecureSkipVerify: true, NextProtos: []string{"http/1.1"}})
			default:
				conn, err = net.Dial("tcp", *addr)
			}
			if err != nil {
				mu.Lock()
				errs++
				mu.Unlock()
				return
			}
			var br *bufio.Reader
			if conn != nil {
				defer conn.Close()
				br = bufio.NewReader(conn)
			}
			next := start.Add(per * time.Duration(c) / time.Duration(*conns))
			var local []time.Duration
			n := 0
			for ; next.Before(end); next = next.Add(per) {
				if *rate > 0 {
					time.Sleep(time.Until(next))
				} else {
					next = time.Now()
				}
				n++
				path, isSlow := "/x", *slowEvery > 0 && (n+c)%*slowEvery == 0
				if isSlow {
					path = "/slow"
				}
				if *bigEvery > 0 && (n+c)%*bigEvery == 1 {
					path, isSlow = "/big", true
				}
				var err error
				if h2 != nil {
					var resp *http.Response
					resp, err = h2.Get(fmt.Sprintf("https://%s%s?c=%d", *addr, path, c))
					if err == nil {
						_, err = io.Copy(io.Discard, resp.Body)
						resp.Body.Close()
						if resp.ProtoMajor != 2 {
							err = fmt.Errorf("answered over HTTP/%d", resp.ProtoMajor)
						}
					}
				} else {
					_, err = fmt.Fprintf(conn, "GET %s?c=%d HTTP/1.1\r\nHost: b\r\n\r\n", path, c)
					if err == nil {
						var resp *http.Response
						resp, err = http.ReadResponse(br, nil)
						if err == nil {
							_, err = io.Copy(io.Discard, resp.Body)
							resp.Body.Close()
						}
					}
				}
				if err != nil {
					mu.Lock()
					errs++
					mu.Unlock()
					return
				}
				if !isSlow && next.After(start.Add(*warm)) {
					local = append(local, time.Since(next))
				}
			}
			mu.Lock()
			lats = append(lats, local...)
			mu.Unlock()
		}(c)
	}
	wg.Wait()
	sort.Slice(lats, func(i, j int) bool { return lats[i] < lats[j] })
	q := func(p float64) time.Duration { return lats[int(float64(len(lats)-1)*p)] }
	if *rate == 0 {
		fmt.Printf("closed loop: %.0f req/s, ", float64(len(lats))/dur.Seconds())
	}
	fmt.Printf("n=%d errs=%d p50=%v p90=%v p99=%v p99.9=%v p99.99=%v max=%v\n",
		len(lats), errs, q(.5), q(.9), q(.99), q(.999), q(.9999), lats[len(lats)-1])
}
