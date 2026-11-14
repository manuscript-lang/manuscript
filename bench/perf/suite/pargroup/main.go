package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
)

type stats struct {
	lines, latency int
	c              [4]int
}

func collect(dir string, out *[]string) {
	entries, _ := os.ReadDir(dir)
	for _, e := range entries {
		p := filepath.Join(dir, e.Name())
		if e.IsDir() {
			collect(p, out)
		} else {
			*out = append(*out, p)
		}
	}
}

func summarize(path string) stats {
	text, _ := os.ReadFile(path)
	var s stats
	for _, line := range strings.Split(string(text), "\n") {
		if line == "" {
			continue
		}
		f := strings.Split(line, " ")
		s.lines++
		v, _ := strconv.Atoi(f[5])
		s.latency += v
		c := int(f[4][0] - '2')
		if c > 3 {
			c = 3
		}
		s.c[c]++
	}
	return s
}

func main() {
	var files []string
	collect(os.Args[1], &files)
	const workers = 4
	parts := make([]stats, workers)
	var wg sync.WaitGroup
	for w := 0; w < workers; w++ {
		wg.Add(1)
		go func(w int) {
			defer wg.Done()
			for i := w; i < len(files); i += workers {
				s := summarize(files[i])
				parts[w].lines += s.lines
				parts[w].latency += s.latency
				for k := 0; k < 4; k++ {
					parts[w].c[k] += s.c[k]
				}
			}
		}(w)
	}
	wg.Wait()
	var t stats
	for _, s := range parts {
		t.lines += s.lines
		t.latency += s.latency
		for k := 0; k < 4; k++ {
			t.c[k] += s.c[k]
		}
	}
	fmt.Printf("files: %d\n", len(files))
	fmt.Printf("lines: %d\n", t.lines)
	fmt.Printf("status: 2xx=%d 3xx=%d 4xx=%d 5xx=%d\n", t.c[0], t.c[1], t.c[2], t.c[3])
	fmt.Printf("latency: %d\n", t.latency)
}
