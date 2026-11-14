package main

import (
	"fmt"
	"slices"
)

func lcg(x int) int { return (x*1103515245 + 12345) % 2147483648 }

func makeInput(n int) []int {
	vocab := [][]int{}
	x := 17
	for w := 0; w < 200; w++ {
		word := []int{}
		x = lcg(x)
		count := 3 + x/11%8
		for k := 0; k < count; k++ {
			x = lcg(x)
			word = append(word, 97+x/13%26)
		}
		vocab = append(vocab, word)
	}
	out := []int{}
	for len(out) < n {
		x = lcg(x)
		out = append(out, vocab[x/17%200]...)
		out = append(out, 32)
	}
	return out
}

func compress(data []int) []int {
	head := make([]int, 65536)
	for i := range head {
		head[i] = -1
	}
	out := []int{}
	n := len(data)
	for i := 0; i < n; {
		best, dist := 0, 0
		if i+3 <= n {
			h := (data[i]*506832829 + data[i+1]*65599 + data[i+2]) % 65536
			cand := head[h]
			head[h] = i
			if cand >= 0 && i-cand < 32768 {
				l := 0
				for i+l < n && l < 255 && data[cand+l] == data[i+l] {
					l++
				}
				if l >= 3 {
					best, dist = l, i-cand
				}
			}
		}
		if best >= 3 {
			out = append(out, 256+best, dist)
			i += best
		} else {
			out = append(out, data[i])
			i++
		}
	}
	return out
}

func decompress(tokens []int) []int {
	out := []int{}
	for i := 0; i < len(tokens); {
		t := tokens[i]
		if t < 256 {
			out = append(out, t)
			i++
		} else {
			l := t - 256
			start := len(out) - tokens[i+1]
			for k := 0; k < l; k++ {
				out = append(out, out[start+k])
			}
			i += 2
		}
	}
	return out
}

func main() {
	data := makeInput(4000000)
	checksum := 0
	for pass := 0; pass < 3; pass++ {
		packed := compress(data)
		if !slices.Equal(decompress(packed), data) {
			fmt.Println("MISMATCH")
		}
		checksum += len(packed)
	}
	fmt.Printf("input %d tokens %d\n", len(data), checksum)
}
