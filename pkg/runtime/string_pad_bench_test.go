package msruntime

import (
	"strconv"
	"testing"
)

var stringPadSink string

func BenchmarkStringPad(b *testing.B) {
	for _, size := range []int{16, 1024, 65536} {
		for _, padding := range []string{"x", "é🙂"} {
			b.Run(strconv.Itoa(size)+"/"+padding, func(b *testing.B) {
				b.ReportAllocs()
				for i := 0; i < b.N; i++ {
					result := String_PadEnd(tctx, "a", size, padding, None[int]())
					if result.Failed {
						b.Fatal("padding failed")
					}
					stringPadSink = result.Val
				}
			})
		}
	}
}
