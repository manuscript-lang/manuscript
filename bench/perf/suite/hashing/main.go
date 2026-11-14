package main

import "fmt"

const mask = 4294967295

func rotr(x, n int) int { return ((x >> n) | (x << (32 - n))) & mask }

func crcTable() []int {
	t := make([]int, 256)
	for i := range t {
		c := i
		for k := 0; k < 8; k++ {
			if c&1 == 1 {
				c = (c >> 1) ^ 3988292384
			} else {
				c >>= 1
			}
		}
		t[i] = c
	}
	return t
}

func crc32(table, data []int) int {
	c := mask
	for _, b := range data {
		c = table[(c^b)&255] ^ (c >> 8)
	}
	return c ^ mask
}

var K = [64]int{
0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

func sha256(data []int) int {
	h := [8]int{0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19}
	msg := append([]int(nil), data...)
	bits := len(data) * 8
	msg = append(msg, 128)
	for len(msg)%64 != 56 {
		msg = append(msg, 0)
	}
	for i := 0; i < 8; i++ {
		msg = append(msg, (bits>>(56-8*i))&255)
	}
	var w [64]int
	for block := 0; block < len(msg); block += 64 {
		for i := 0; i < 16; i++ {
			j := block + i*4
			w[i] = msg[j]<<24 | msg[j+1]<<16 | msg[j+2]<<8 | msg[j+3]
		}
		for i := 16; i < 64; i++ {
			x, y := w[i-15], w[i-2]
			s0 := rotr(x, 7) ^ rotr(x, 18) ^ (x >> 3)
			s1 := rotr(y, 17) ^ rotr(y, 19) ^ (y >> 10)
			w[i] = (w[i-16] + s0 + w[i-7] + s1) & mask
		}
		a, b, c, d, e, f, g, hh := h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7]
		for i := 0; i < 64; i++ {
			big1 := rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
			ch := (e & f) ^ ((e ^ mask) & g)
			t1 := (hh + big1 + ch + K[i] + w[i]) & mask
			big0 := rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
			maj := (a & b) ^ (a & c) ^ (b & c)
			t2 := (big0 + maj) & mask
			hh, g, f, e, d, c, b, a = g, f, e, (d+t1)&mask, c, b, a, (t1+t2)&mask
		}
		for i, v := range [8]int{a, b, c, d, e, f, g, hh} {
			h[i] = (h[i] + v) & mask
		}
	}
	return h[0] ^ h[7]
}

func main() {
	data := make([]int, 0, 8000000)
	x := 5
	for i := 0; i < 8000000; i++ {
		x = (x*1103515245 + 12345) & 2147483647
		data = append(data, (x>>16)%256)
	}
	fmt.Printf("crc32 %d\n", crc32(crcTable(), data))
	fmt.Printf("sha256 %d\n", sha256(data))
}
