package main

import (
	"fmt"
	"io"
	"os"
	"strings"
)

func main() {
	raw, _ := io.ReadAll(os.Stdin)
	hits := 0
	for _, l := range strings.Split(string(raw), "\n") {
		if strings.Contains(l, " POST /api/v2/item/17") && strings.Contains(l, " 500 ") {
			hits++
		}
	}
	fmt.Printf("hits: %d\n", hits)
}
