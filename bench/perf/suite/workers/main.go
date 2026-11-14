package main

import (
	"fmt"
	"sync"
)

func chunkChecksum(chunk int) int {
	var hist [256]int
	x := chunk*7919 + 1
	h := 0
	for i := 0; i < 200000; i++ {
		x = (x * 48271) % 2147483647
		hist[x%256]++
		h = (h*31 + x) % 1000000007
	}
	for b := 0; b < 256; b++ {
		h = (h*131 + hist[b]) % 1000000007
	}
	return h
}

func main() {
	var wg sync.WaitGroup
	results := make([]int, 128)
	for chunk := 0; chunk < 128; chunk++ {
		wg.Add(1)
		go func(c int) {
			defer wg.Done()
			results[c] = chunkChecksum(c)
		}(chunk)
	}
	wg.Wait()
	total := 0
	for _, r := range results {
		total += r
	}
	fmt.Printf("chunks 128 checksum %d\n", total)
}
