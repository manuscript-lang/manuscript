package main

import (
	"crypto/sha256"
	"crypto/sha512"
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"hash/adler32"
	"hash/crc32"
	"hash/crc64"
	"hash/fnv"
	"time"
)

func lap(name string, t time.Time) { fmt.Println(name, time.Since(t).Milliseconds()) }

func main() {
	n := 64 * 1024 * 1024
	data := make([]byte, n)
	s := 12345
	for i := range data {
		s = (s*1103515245 + 12345) % 2147483648
		data[i] = byte((s / 65536) % 256)
	}
	t := time.Now()
	a := crc32.ChecksumIEEE(data)
	lap("crc32", t)
	t = time.Now()
	b := adler32.Checksum(data)
	lap("adler32", t)
	t = time.Now()
	c := sha256.Sum256(data)
	lap("sha256", t)
	t = time.Now()
	d := sha512.Sum512(data)
	lap("sha512", t)
	t = time.Now()
	h := fnv.New64a()
	h.Write(data)
	f := h.Sum64()
	lap("fnv1a64", t)
	t = time.Now()
	g := crc64.Checksum(data, crc64.MakeTable(crc64.ISO))
	lap("crc64", t)
	t = time.Now()
	e64 := base64.StdEncoding.EncodeToString(data)
	lap("b64enc", t)
	t = time.Now()
	dd, _ := base64.StdEncoding.DecodeString(e64)
	lap("b64dec", t)
	t = time.Now()
	hx := hex.EncodeToString(data)
	lap("hexenc", t)
	t = time.Now()
	hd, _ := hex.DecodeString(hx)
	lap("hexdec", t)
	fmt.Println(a, b, len(c), len(d), f, g, len(dd), len(hd))
}
