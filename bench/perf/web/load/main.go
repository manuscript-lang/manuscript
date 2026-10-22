// Keep-alive HTTP/1.1 load generator.
//
//	load <port> <conns> <seconds> <path>  sends requests back to back on each connection and
//	                                      prints req/s, p50, p99 and failures; {c} in the path
//	                                      becomes the connection number
//	load idle <port> <n>                  opens n connections, sends one request on each, then
//	                                      holds them open until killed
package main

import (
	"bufio"
	"errors"
	"fmt"
	"net"
	"os"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

func main() {
	if len(os.Args) == 4 && os.Args[1] == "idle" {
		idle(os.Args[2], atoi(os.Args[3]))
		return
	}
	if len(os.Args) != 5 {
		fmt.Fprintln(os.Stderr, "usage: load <port> <conns> <seconds> <path> | load idle <port> <n>")
		os.Exit(2)
	}
	run(os.Args[1], atoi(os.Args[2]), atoi(os.Args[3]), os.Args[4])
}

func run(port string, conns, secs int, path string) {
	deadline := time.Now().Add(time.Duration(secs) * time.Second)
	var mu sync.Mutex
	var lat []time.Duration
	total, bad := 0, 0
	var wg sync.WaitGroup
	for c := 0; c < conns; c++ {
		wg.Add(1)
		go func(c int) {
			defer wg.Done()
			req := []byte("GET " + strings.ReplaceAll(path, "{c}", strconv.Itoa(c)) + " HTTP/1.1\r\nHost: x\r\n\r\n")
			conn, err := net.Dial("tcp", "127.0.0.1:"+port)
			if err != nil {
				mu.Lock()
				bad++
				mu.Unlock()
				return
			}
			defer conn.Close()
			r := bufio.NewReaderSize(conn, 65536)
			var mine []time.Duration
			n, b := 0, 0
			for time.Now().Before(deadline) {
				t := time.Now()
				if _, err := conn.Write(req); err != nil {
					b++
					break
				}
				status, err := readResponse(r)
				if err != nil {
					b++
					break
				}
				if status != 200 {
					b++
				}
				mine = append(mine, time.Since(t))
				n++
			}
			mu.Lock()
			lat = append(lat, mine...)
			total += n
			bad += b
			mu.Unlock()
		}(c)
	}
	wg.Wait()
	sort.Slice(lat, func(i, j int) bool { return lat[i] < lat[j] })
	p := func(q float64) time.Duration {
		if len(lat) == 0 {
			return 0
		}
		return lat[int(float64(len(lat)-1)*q)]
	}
	fmt.Printf("req/s %.0f  p50 %v  p99 %v  failed %d\n", float64(total)/float64(secs), p(.5), p(.99), bad)
}

func idle(port string, n int) {
	conns := make([]net.Conn, 0, n)
	for i := 0; i < n; i++ {
		c, err := net.Dial("tcp", "127.0.0.1:"+port)
		if err != nil {
			fmt.Println("dial error after", i, err)
			break
		}
		if _, err := c.Write([]byte("GET /health HTTP/1.1\r\nHost: x\r\n\r\n")); err != nil {
			fmt.Println("write error after", i, err)
			break
		}
		if _, err := readResponse(bufio.NewReader(c)); err != nil {
			fmt.Println("read error after", i, err)
			break
		}
		conns = append(conns, c)
	}
	fmt.Println("holding", len(conns))
	for {
		time.Sleep(time.Hour)
	}
}

func atoi(s string) int {
	n, err := strconv.Atoi(s)
	if err != nil {
		fmt.Fprintln(os.Stderr, "not a number:", s)
		os.Exit(2)
	}
	return n
}

// readResponse reads one response and returns its status.
func readResponse(r *bufio.Reader) (int, error) {
	line, err := r.ReadString('\n')
	if err != nil {
		return 0, err
	}
	status := 0
	fmt.Sscanf(line, "HTTP/1.1 %d", &status)
	length, chunked := -1, false
	for {
		h, err := r.ReadString('\n')
		if err != nil {
			return 0, err
		}
		if h == "\r\n" {
			break
		}
		name, value, _ := strings.Cut(strings.TrimRight(h, "\r\n"), ":")
		value = strings.TrimSpace(value)
		switch strings.ToLower(name) {
		case "content-length":
			length, _ = strconv.Atoi(value)
		case "transfer-encoding":
			chunked = strings.EqualFold(value, "chunked")
		}
	}
	if !chunked {
		if length > 0 {
			_, err = r.Discard(length)
		}
		return status, err
	}
	for {
		l, err := r.ReadString('\n')
		if err != nil {
			return 0, err
		}
		size, err := strconv.ParseInt(strings.TrimSpace(strings.SplitN(l, ";", 2)[0]), 16, 64)
		if err != nil {
			return 0, errors.New("bad chunk size")
		}
		if _, err := r.Discard(int(size) + 2); err != nil {
			return 0, err
		}
		if size == 0 {
			return status, nil
		}
	}
}
