package msruntime

import (
	"fmt"
	"strings"
	"testing"
)

var joinedString string

func BenchmarkListJoin(b *testing.B) {
	for _, n := range []int{0, 1, 32, 1024} {
		parts := NewList(strings.Split(strings.Repeat("hello🙂,", n), ",")...)
		parts.Items = parts.Items[:n]
		b.Run(fmt.Sprint(n), func(b *testing.B) {
			b.ReportAllocs()
			for i := 0; i < b.N; i++ {
				joinedString = List_Join(tctx, parts, ",")
			}
		})
	}
}
