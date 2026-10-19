package main

import (
	"hash/crc32"
	"math/rand"
	"strconv"
	"strings"

	rt "github.com/manuscript-lang/manuscript/pkg/runtime"
)

// chunkStream serves data in chunks of at most chunk bytes.
type chunkStream struct {
	data  []byte
	chunk int
}

func (c *chunkStream) Close(*rt.Execution) rt.Unit { return rt.Unit{} }

func (c *chunkStream) Read(_ *rt.Execution, max rt.Option[int]) rt.Result[rt.Option[*rt.Bytes], rt.IoError] {
	if len(c.data) == 0 {
		return rt.Ok[rt.Option[*rt.Bytes], rt.IoError](rt.None[*rt.Bytes]())
	}
	n := min(c.chunk, len(c.data))
	if max.Some {
		n = min(n, max.Val)
	}
	b := append([]byte(nil), c.data[:n]...)
	c.data = c.data[n:]
	return rt.Ok[rt.Option[*rt.Bytes], rt.IoError](rt.Some(rt.NewBytes(b)))
}

func formatValue(name string) rt.CompressionFormat {
	switch name {
	case "gzip":
		return rt.CompressionFormat_Gzip{}
	case "zlib":
		return rt.CompressionFormat_Zlib{}
	}
	return rt.CompressionFormat_Deflate{}
}

// gzipWithHeader wraps a raw deflate body in a gzip member with optional header fields.
func gzipWithHeader(body []byte, plain []byte, flags byte, extra, name, comment string) []byte {
	h := []byte{0x1f, 0x8b, 8, flags, 0, 0, 0, 0, 0, 255}
	if flags&4 != 0 {
		h = append(h, byte(len(extra)), byte(len(extra)>>8))
		h = append(h, extra...)
	}
	if flags&8 != 0 {
		h = append(h, name...)
		h = append(h, 0)
	}
	if flags&16 != 0 {
		h = append(h, comment...)
		h = append(h, 0)
	}
	if flags&2 != 0 {
		c := crc32.ChecksumIEEE(h)
		h = append(h, byte(c), byte(c>>8))
	}
	crc := crc32.ChecksumIEEE(plain)
	n := uint32(len(plain))
	out := append(h, body...)
	return append(out, byte(crc), byte(crc>>8), byte(crc>>16), byte(crc>>24), byte(n), byte(n>>8), byte(n>>16), byte(n>>24))
}

func genCompressStream(dir string) {
	r := &recorder{}
	rng := rand.New(rand.NewSource(33))
	noise := make([]byte, 300)
	rng.Read(noise)
	plains := [][]byte{{}, []byte("a"), []byte("hello hello hello"), make([]byte, 700), noise, []byte(strings.Repeat("the quick brown fox ", 3500))}
	id := 0
	emit := func(format string, data []byte, plainLen int, limits []rt.Option[int]) {
		id++
		r.row("in", strconv.Itoa(id), hb(rt.NewBytes(data)))
		for _, lim := range limits {
			for _, cfg := range [][2]int{{1, 1}, {3, 7}, {4096, 65536}} {
				s := rt.CompressionFormat_DecompressStream(nil, formatValue(format), &chunkStream{data: append([]byte(nil), data...), chunk: cfg[0]}, lim)
				var out []byte
				status := "ok"
				for {
					res := s.Read(nil, rt.Some(cfg[1]))
					if res.Failed {
						status = "err " + errName(res.Err)
						break
					}
					if !res.Val.Some {
						break
					}
					out = append(out, res.Val.Val.Data...)
				}
				r.row("dec", format, strconv.Itoa(id), opt(lim), strconv.Itoa(cfg[0]), strconv.Itoa(cfg[1]), "=>", strconv.Itoa(len(out)), strconv.FormatUint(uint64(crc32.ChecksumIEEE(out)), 16), status)
			}
		}
		_ = plainLen
	}
	for _, f := range []string{"gzip", "zlib", "deflate"} {
		for _, p := range plains {
			for _, level := range []int{0, 6} {
				if level == 0 && len(p) > 1000 {
					continue
				}
				packed := rt.Compress_Compress(nil, rt.NewBytes(p), f, level, rt.Option[int]{}).Val.Data
				limits := []rt.Option[int]{{}, rt.Some(len(p)), rt.Some(-1)}
				if len(p) > 0 {
					limits = append(limits, rt.Some(len(p)-1))
				}
				emit(f, packed, len(p), limits)
				none := []rt.Option[int]{{}}
				variants := [][]byte{packed[:len(packed)/2], packed[:len(packed)-1], packed[:min(1, len(packed))], nil,
					append(append([]byte{}, packed...), 0), append(append([]byte{}, packed...), 1, 2, 3, 4, 5), append(append([]byte{}, packed...), packed...)}
				for i := 0; i < 4 && len(packed) > 0; i++ {
					v := append([]byte{}, packed...)
					v[rng.Intn(len(v))] ^= byte(1 << uint(rng.Intn(8)))
					variants = append(variants, v)
				}
				for _, v := range variants {
					emit(f, v, len(p), none)
				}
			}
		}
	}
	// Gzip header fields around a raw deflate body, and members of different payloads.
	body := rt.Compress_Compress(nil, rt.NewBytes([]byte("header test header test")), "deflate", 6, rt.Option[int]{}).Val.Data
	plain := []byte("header test header test")
	for _, flags := range []byte{0, 2, 4, 8, 16, 2 | 4 | 8 | 16, 0xe0, 1} {
		emit("gzip", gzipWithHeader(body, plain, flags, "xy", "name.txt", "a comment"), len(plain), []rt.Option[int]{{}})
	}
	emit("gzip", gzipWithHeader(body, plain, 8, "", strings.Repeat("n", 600), ""), len(plain), []rt.Option[int]{{}})
	emit("gzip", gzipWithHeader(body, plain, 4, strings.Repeat("e", 70000), "", ""), len(plain), []rt.Option[int]{{}})
	a := rt.Compress_Compress(nil, rt.NewBytes([]byte("first ")), "gzip", 6, rt.Option[int]{}).Val.Data
	b := rt.Compress_Compress(nil, rt.NewBytes([]byte("second")), "gzip", 6, rt.Option[int]{}).Val.Data
	emit("gzip", append(append([]byte{}, a...), b...), 12, []rt.Option[int]{{}, rt.Some(11), rt.Some(12)})
	emit("gzip", append(append(append([]byte{}, a...), b...), 0x1f), 12, []rt.Option[int]{{}})
	emit("gzip", append(append(append([]byte{}, a...), b...), 0x1f, 0x8b, 8), 12, []rt.Option[int]{{}})
	r.write(dir, "stream.tsv")
}
