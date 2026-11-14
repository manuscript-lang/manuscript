package main

import (
	"fmt"
	"io"
	"os"
	"sort"
	"strconv"
	"strings"
)

// RFC 4180 records; a field with quotes is unescaped into an owned string.
func parse(b []byte) [][]string {
	var rows [][]string
	var row []string
	var field []byte
	inQuotes := false
	for i := 0; i < len(b); i++ {
		c := b[i]
		switch {
		case inQuotes:
			if c == '"' {
				if i+1 < len(b) && b[i+1] == '"' {
					field = append(field, '"')
					i++
				} else {
					inQuotes = false
				}
			} else {
				field = append(field, c)
			}
		case c == '"' && len(field) == 0:
			inQuotes = true
		case c == ',':
			row = append(row, string(field))
			field = field[:0]
		case c == '\n':
			row = append(row, string(field))
			field = field[:0]
			rows = append(rows, row)
			row = nil
		default:
			field = append(field, c)
		}
	}
	return rows
}

func main() {
	raw, _ := io.ReadAll(os.Stdin)
	rows := parse(raw)
	type agg struct{ n, c int }
	regions := map[string]*agg{}
	products := map[string]int{}
	quoted := 0
	for _, r := range rows[1:] {
		q, _ := strconv.Atoi(r[3])
		p, _ := strconv.Atoi(r[4])
		cents := q * p
		e := regions[r[1]]
		if e == nil {
			e = &agg{}
			regions[r[1]] = e
		}
		e.n++
		e.c += cents
		products[r[2]] += cents
		if strings.Contains(r[5], ",") {
			quoted++
		}
	}
	fmt.Printf("rows: %d\n", len(rows)-1)
	fmt.Printf("quoted: %d\n", quoted)
	keys := make([]string, 0, len(regions))
	for k := range regions {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	for _, k := range keys {
		fmt.Printf("%s %d %d\n", k, regions[k].n, regions[k].c)
	}
	type kv struct {
		k string
		v int
	}
	ps := make([]kv, 0, len(products))
	for k, v := range products {
		ps = append(ps, kv{k, v})
	}
	sort.Slice(ps, func(i, j int) bool {
		if ps[i].v != ps[j].v {
			return ps[i].v > ps[j].v
		}
		return ps[i].k < ps[j].k
	})
	for _, e := range ps[:5] {
		fmt.Printf("%s %d\n", e.k, e.v)
	}
}
