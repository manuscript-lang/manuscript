package msruntime

import (
	"bufio"
	"bytes"
	"io"
	"strings"
	"testing"
)

var lineBenchSink int

func BenchmarkReadLinePayload(b *testing.B) {
	data := []byte(strings.Repeat("2026-03-01T00:00:00Z GET /api/users/1234 200\n", 8192))
	for _, mode := range []string{"Text", "Presence", "Go"} {
		b.Run(mode, func(b *testing.B) {
			b.ReportAllocs()
			stream := &bufferedLineProbe{}
			count := 0
			b.ResetTimer()
			for range b.N {
				n := 0
				if mode == "Go" {
					reader := bufio.NewReader(bytes.NewReader(data))
					for {
						_, err := reader.ReadString('\n')
						if err == io.EOF {
							break
						}
						if err != nil {
							b.Fatal(err)
						}
						n++
					}
				} else {
					stream.ahead.buf = data
					for {
						present := false
						if mode == "Presence" {
							present = Io_HasLine(nil, stream, None[int]())
						} else {
							line := Io_ReadLine(nil, stream, None[int]())
							present = !line.Failed && line.Val.Some
						}
						if !present {
							break
						}
						n++
					}
				}
				if n != 8192 {
					b.Fatal(n)
				}
				count += n
			}
			lineBenchSink = count
		})
	}
}
