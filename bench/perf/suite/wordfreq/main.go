package main

import (
	"fmt"
	"io"
	"os"
	"sort"
	"strings"
)

func main() {
	raw, _ := io.ReadAll(os.Stdin)
	data := strings.ToLower(string(raw))
	counts := map[string]int{}
	total := 0
	for _, w := range strings.FieldsFunc(data, func(c rune) bool { return c == ' ' || c == '.' || c == '\n' }) {
		total++
		counts[w]++
	}
	fmt.Printf("words: %d\n", total)
	fmt.Printf("distinct: %d\n", len(counts))
	type kv struct {
		k string
		v int
	}
	ranked := make([]kv, 0, len(counts))
	for k, v := range counts {
		ranked = append(ranked, kv{k, v})
	}
	sort.Slice(ranked, func(i, j int) bool {
		if ranked[i].v != ranked[j].v {
			return ranked[i].v > ranked[j].v
		}
		return ranked[i].k < ranked[j].k
	})
	for _, e := range ranked[:10] {
		fmt.Printf("%s %d\n", e.k, e.v)
	}
}
