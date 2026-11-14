package main

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"
)

func main() {
	raw, _ := io.ReadAll(os.Stdin)
	out := bufio.NewWriterSize(os.Stdout, 1<<20)
	defer out.Flush()
	total := 0
	for _, line := range strings.Split(string(raw), "\n") {
		if line == "" {
			continue
		}
		name, score, _ := strings.Cut(line, " ")
		s, _ := strconv.Atoi(score)
		total += s
		fmt.Fprintf(out, "%-12s %8d %d\n", name, s, s*3/7)
	}
	fmt.Fprintf(out, "total %d\n", total)
}
