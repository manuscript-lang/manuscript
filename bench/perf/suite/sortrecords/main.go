package main

import (
	"fmt"
	"io"
	"os"
	"sort"
	"strconv"
	"strings"
)

type rec struct {
	name  string
	score int
}

func main() {
	raw, _ := io.ReadAll(os.Stdin)
	var recs []rec
	for _, line := range strings.Split(string(raw), "\n") {
		if line == "" {
			continue
		}
		name, score, _ := strings.Cut(line, " ")
		v, _ := strconv.Atoi(score)
		recs = append(recs, rec{name, v})
	}
	sort.Slice(recs, func(i, j int) bool {
		if recs[i].score != recs[j].score {
			return recs[i].score > recs[j].score
		}
		return recs[i].name < recs[j].name
	})
	check := 0
	for i, r := range recs {
		check = (check*31 + r.score + i) % 1000000007
	}
	fmt.Printf("records: %d\n", len(recs))
	fmt.Printf("checksum: %d\n", check)
	for _, i := range []int{0, 1, 2, len(recs) - 1} {
		fmt.Printf("%s %d\n", recs[i].name, recs[i].score)
	}
}
