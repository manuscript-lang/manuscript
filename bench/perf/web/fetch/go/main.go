// Fetch benchmark client and file server.
//
//	main get <url> <connections> <seconds>   keep-alive GETs; prints requests per second
//	main serve <port> <dir>                  static file server for the bodies
package main

import (
	"fmt"
	"io"
	"net/http"
	"os"
	"strconv"
	"sync"
	"sync/atomic"
	"time"
)

func main() {
	switch os.Args[1] {
	case "serve":
		fmt.Fprintln(os.Stderr, http.ListenAndServe("127.0.0.1:"+os.Args[2], http.FileServer(http.Dir(os.Args[3]))))
		os.Exit(1)
	case "get":
		conns, _ := strconv.Atoi(os.Args[3])
		secs, _ := strconv.Atoi(os.Args[4])
		var done int64
		var wg sync.WaitGroup
		client := &http.Client{Transport: &http.Transport{MaxIdleConnsPerHost: conns}}
		end := time.Now().Add(time.Duration(secs) * time.Second)
		for i := 0; i < conns; i++ {
			wg.Add(1)
			go func() {
				defer wg.Done()
				for time.Now().Before(end) {
					r, err := client.Get(os.Args[2])
					if err != nil {
						return
					}
					io.Copy(io.Discard, r.Body)
					r.Body.Close()
					atomic.AddInt64(&done, 1)
				}
			}()
		}
		wg.Wait()
		fmt.Println("req/s", done/int64(secs))
	}
}
