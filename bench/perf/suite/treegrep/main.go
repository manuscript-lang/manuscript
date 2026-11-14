package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

func scan(dir string, files, matches *int) {
	entries, _ := os.ReadDir(dir)
	for _, e := range entries {
		path := filepath.Join(dir, e.Name())
		if e.IsDir() {
			scan(path, files, matches)
			continue
		}
		*files++
		text, _ := os.ReadFile(path)
		for _, line := range strings.Split(string(text), "\n") {
			if strings.Contains(line, " POST /api/v2/item/17") && strings.Contains(line, " 500 ") {
				*matches++
			}
		}
	}
}

func main() {
	files, matches := 0, 0
	scan(os.Args[1], &files, &matches)
	fmt.Printf("files: %d\n", files)
	fmt.Printf("matches: %d\n", matches)
}
