package main

import (
	"fmt"
	"sync"
)

func countPrimes(lo, hi int) int {
	count := 0
	for n := lo; n < hi; n++ {
		if n < 2 {
			continue
		}
		isPrime := true
		for d := 2; d*d <= n; d++ {
			if n%d == 0 {
				isPrime = false
				break
			}
		}
		if isPrime {
			count++
		}
	}
	return count
}

func small(i int) int {
	t := 0
	for k := 0; k < 200; k++ {
		t += (i + k) % 7
	}
	return t
}

func main() {
	var wg sync.WaitGroup
	results := make([]int, 16)
	for chunk := 0; chunk < 16; chunk++ {
		wg.Add(1)
		go func(c int) {
			defer wg.Done()
			results[c] = countPrimes(c*250000, c*250000+250000)
		}(chunk)
	}
	wg.Wait()
	primes := 0
	for _, r := range results {
		primes += r
	}

	// One goroutine per small task, as the Manuscript version creates one promise per task.
	small_ := make([]int, 100000)
	for i := 0; i < 100000; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			small_[i] = small(i)
		}(i)
	}
	wg.Wait()
	total := 0
	for _, r := range small_ {
		total += r
	}
	fmt.Printf("primes %d small %d\n", primes, total)
}
