package main

import (
	"encoding/json"
	"net/http"
	"os"
	"strconv"
	"strings"
)

type item struct {
	ID   int    `json:"id"`
	Name string `json:"name"`
}

var spin = func() int {
	n, err := strconv.Atoi(os.Getenv("SPIN"))
	if err != nil {
		return 1000000
	}
	return n
}()

func main() {
	addr := "127.0.0.1:8083"
	if len(os.Args) > 1 {
		addr = "127.0.0.1:" + os.Args[1]
	}
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		spun := 0
		if strings.HasPrefix(r.URL.Path, "/slow") {
			x := 1
			for i := 0; i < spin; i++ {
				x = (x*31 + i) % 1000003
			}
			spun = x
		}
		count := 64
		if strings.HasPrefix(r.URL.Path, "/big") {
			count = 4096
		}
		items := make([]item, 0, count)
		for i := 0; i < count; i++ {
			items = append(items, item{i, "item-" + strconv.Itoa(i)})
		}
		body, _ := json.Marshal(map[string]any{"path": r.URL.Path, "spun": spun, "items": items})
		w.Header().Set("Content-Type", "application/json")
		w.Write(body)
	})
	http.ListenAndServe(addr, nil)
}
