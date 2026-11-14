package main

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"sort"
)

func main() {
	raw, _ := io.ReadAll(os.Stdin)
	var root []map[string]interface{}
	if err := json.Unmarshal(raw, &root); err != nil {
		panic(err)
	}
	scores := map[string]int{}
	tags := map[string]int{}
	records, active, nameBytes := 0, 0, 0
	for _, r := range root {
		records++
		if u, ok := r["user"].(string); ok {
			if s, ok := r["score"].(float64); ok {
				scores[u] += int(s)
			}
		}
		if ts, ok := r["tags"].([]interface{}); ok {
			for _, t := range ts {
				if s, ok := t.(string); ok {
					tags[s]++
				}
			}
		}
		if a, ok := r["active"].(bool); ok && a {
			active++
		}
		if n, ok := r["name"].(string); ok {
			nameBytes += len(n)
		}
	}
	fmt.Printf("records: %d\n", records)
	fmt.Printf("active: %d\n", active)
	fmt.Printf("name bytes: %d\n", nameBytes)
	type kv struct {
		k string
		v int
	}
	ranked := make([]kv, 0, len(scores))
	for k, v := range scores {
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
	keys := make([]string, 0, len(tags))
	for k := range tags {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	for _, k := range keys {
		fmt.Printf("%s %d\n", k, tags[k])
	}
}
