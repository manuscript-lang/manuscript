package main

import (
	"fmt"
	"io"
	"os"
	"sort"
	"strconv"
	"strings"
)

func main() {
	raw, _ := io.ReadAll(os.Stdin)
	data := string(raw)
	rows, latency := 0, 0
	classes := [4]int{}
	paths := map[string]int{}
	for _, line := range strings.Split(data, "\n") {
		if line == "" {
			continue
		}
		f := strings.Split(line, " ")
		rows++
		v, _ := strconv.Atoi(f[5])
		latency += v
		classes[f[4][0]-'2']++
		paths[f[3]]++
	}
	fmt.Printf("lines: %d\n", rows)
	fmt.Printf("status: 2xx=%d 3xx=%d 4xx=%d 5xx=%d\n", classes[0], classes[1], classes[2], classes[3])
	fmt.Printf("latency: %d\n", latency)
	type kv struct {
		k string
		v int
	}
	ranked := make([]kv, 0, len(paths))
	for k, v := range paths {
		ranked = append(ranked, kv{k, v})
	}
	sort.Slice(ranked, func(i, j int) bool {
		if ranked[i].v != ranked[j].v {
			return ranked[i].v > ranked[j].v
		}
		return ranked[i].k < ranked[j].k
	})
	for _, e := range ranked[:5] {
		fmt.Printf("%s %d\n", e.k, e.v)
	}
}
