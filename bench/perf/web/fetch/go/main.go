// Fetch benchmark client and file server.
//
//	main get <url> <connections> <seconds>   keep-alive GETs; prints requests per second
//	main serve <port> <dir>                  static file server for the bodies
package main

import (
	"bytes"
	"compress/gzip"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"sync"
	"sync/atomic"
	"time"
)

func main() {
	switch os.Args[1] {
	case "serve":
		fmt.Fprintln(os.Stderr, http.ListenAndServe("127.0.0.1:"+os.Args[2], framings(os.Args[3])))
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

// framings serves the files in dir as they are, plus "/chunked/<name>" (chunked, 64 KiB flushes,
// no Content-Length) and "/gzip/<name>" (gzip-compressed with Content-Length).
func framings(dir string) http.Handler {
	files := http.FileServer(http.Dir(dir))
	mux := http.NewServeMux()
	mux.Handle("/", files)
	mux.HandleFunc("/chunked/", func(w http.ResponseWriter, r *http.Request) {
		data, err := os.ReadFile(filepath.Join(dir, filepath.Base(r.URL.Path)))
		if err != nil {
			http.NotFound(w, r)
			return
		}
		f := w.(http.Flusher)
		for len(data) > 0 {
			n := min(len(data), 65536)
			w.Write(data[:n])
			f.Flush()
			data = data[n:]
		}
	})
	var mu sync.Mutex
	zipped := map[string][]byte{}
	mux.HandleFunc("/gzip/", func(w http.ResponseWriter, r *http.Request) {
		name := filepath.Base(r.URL.Path)
		mu.Lock()
		z, ok := zipped[name]
		if !ok {
			data, err := os.ReadFile(filepath.Join(dir, name))
			if err != nil {
				mu.Unlock()
				http.NotFound(w, r)
				return
			}
			var b bytes.Buffer
			g := gzip.NewWriter(&b)
			g.Write(data)
			g.Close()
			z = b.Bytes()
			zipped[name] = z
		}
		mu.Unlock()
		w.Header().Set("Content-Encoding", "gzip")
		w.Header().Set("Content-Length", fmt.Sprint(len(z)))
		w.Write(z)
	})
	return mux
}
