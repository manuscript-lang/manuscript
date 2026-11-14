package main

import (
	"fmt"
	"sort"
	"strings"
)

func lcg(x int) int { return (x*1103515245 + 12345) % 2147483648 }

func pad(s string, n int, fill string, left bool) string {
	if len(s) >= n {
		return s
	}
	p := strings.Repeat(fill, n-len(s))
	if left {
		return p + s
	}
	return s + p
}

func main() {
	x := 21
	words := make([]string, 0, 300000)
	for i := 0; i < 300000; i++ {
		x = lcg(x)
		words = append(words, fmt.Sprintf("  Item-%d_%d ", x%100000, x/3%977))
	}
	upperLen, replaced, found, padded := 0, 0, 0, 0
	for _, w := range words {
		t := strings.TrimSpace(w)
		upperLen += len(strings.ToUpper(t))
		replaced += len(strings.ReplaceAll(strings.ReplaceAll(t, "_", "--"), "Item", "I"))
		if strings.Contains(t, "77") {
			found++
		}
		if i := strings.Index(t, "-"); i >= 0 {
			found += i
		}
		padded += len(pad(t, 20, ".", true)) + len(pad(strings.ToLower(t), 24, "*", false))
	}
	joined := make([]string, len(words))
	for i, w := range words {
		joined[i] = strings.TrimSpace(w)
	}
	sort.Strings(joined)
	sortedSample := 0
	for i := 0; i < len(joined); i += 1000 {
		sortedSample += len(joined[i]) + int(joined[i][5])
	}
	var sb strings.Builder
	for _, w := range joined {
		if sb.Len() > 200000 {
			break
		}
		sb.WriteString(w)
		sb.WriteByte(',')
	}
	parts := len(strings.Split(sb.String(), ","))
	fmt.Printf("upper %d replaced %d found %d padded %d sorted %d parts %d\n", upperLen, replaced, found, padded, sortedSample, parts)
}
