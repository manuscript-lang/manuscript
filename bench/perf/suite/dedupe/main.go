package main

import (
	"fmt"
	"io"
	"os"
	"strings"
)

func main() {
	raw, _ := io.ReadAll(os.Stdin)
	lines := map[string]int{}
	names := map[string]int{}
	total := 0
	for _, line := range strings.Split(string(raw), "\n") {
		if line == "" {
			continue
		}
		total++
		lines[line]++
		name, _, _ := strings.Cut(line, " ")
		names[name]++
	}
	most, count := "", 0
	for k, v := range lines {
		if v > count || (v == count && k < most) {
			most, count = k, v
		}
	}
	fmt.Printf("lines: %d\n", total)
	fmt.Printf("distinct lines: %d\n", len(lines))
	fmt.Printf("distinct names: %d\n", len(names))
	fmt.Printf("most repeated: %s x%d\n", most, count)
}
