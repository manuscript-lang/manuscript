// Benchmark server: main <port> <data-dir>. Answers the same requests as ../ms.
package main

import (
	"bytes"
	"fmt"
	"net"
	"net/http"
	"os"
	"strconv"
	"strings"
)

const users = 1000

func score(id int) int { return id * 7919 % 1000 }

// pickAfter returns the next entry after (prevID, prevScore) in score-descending, id-ascending order.
func pickAfter(prevID, prevScore int) int {
	best, bestScore := -1, -1
	for id := 0; id < users; id++ {
		sc := score(id)
		if (sc < prevScore || (sc == prevScore && id > prevID)) && sc > bestScore {
			best, bestScore = id, sc
		}
	}
	return best
}

func top(k int) string {
	var sb strings.Builder
	sb.WriteByte('[')
	prevID, prevScore := -1, 1000
	for n := 0; n < k; n++ {
		best := pickAfter(prevID, prevScore)
		if n > 0 {
			sb.WriteByte(',')
		}
		fmt.Fprintf(&sb, `{"id":%d,"score":%d}`, best, score(best))
		prevID, prevScore = best, score(best)
	}
	sb.WriteString("]\n")
	return sb.String()
}

func main() {
	if len(os.Args) != 3 {
		os.Exit(2)
	}
	dir := os.Args[2]
	payload := bytes.Repeat([]byte("0123456789abcdef"), 65536)
	mux := http.NewServeMux()
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) { w.Write([]byte("ok\n")) })
	mux.HandleFunc("/user/", func(w http.ResponseWriter, r *http.Request) {
		id, err := strconv.Atoi(strings.TrimPrefix(r.URL.Path, "/user/"))
		if err != nil || id < 0 || id >= users {
			http.Error(w, "not found", 404)
			return
		}
		fmt.Fprintf(w, `{"id":%d,"name":"user%d","score":%d}`+"\n", id, id, score(id))
	})
	mux.HandleFunc("/top", func(w http.ResponseWriter, r *http.Request) {
		k, err := strconv.Atoi(r.URL.Query().Get("n"))
		if err != nil || k < 1 || k > 50 {
			http.Error(w, "bad n", 400)
			return
		}
		w.Write([]byte(top(k)))
	})
	// Resolve localhost, write 1 MiB to the connection's own file, read it back.
	mux.HandleFunc("/io", func(w http.ResponseWriter, r *http.Request) {
		addrs, err := net.LookupHost("localhost")
		if err != nil {
			http.Error(w, "lookup failed", 500)
			return
		}
		path := dir + "/g" + r.URL.RawQuery + ".bin"
		if err := os.WriteFile(path, payload, 0o600); err != nil {
			http.Error(w, "file failed", 500)
			return
		}
		got, err := os.ReadFile(path)
		if err != nil {
			http.Error(w, "file failed", 500)
			return
		}
		fmt.Fprintf(w, "%d %d\n", len(addrs), len(got))
	})
	if err := http.ListenAndServe("127.0.0.1:"+os.Args[1], mux); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
