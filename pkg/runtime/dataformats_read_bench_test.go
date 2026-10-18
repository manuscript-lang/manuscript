package msruntime

import (
	"math"
	"strings"
	"testing"
)

var dfReadBenchmarkResult []byte

func BenchmarkDFReadBounded(b *testing.B) {
	ctx := RootExecution()
	for _, tt := range []struct {
		name      string
		size, max int
	}{
		{"empty", 0, 0},
		{"64B", 64, 64},
		{"1KiB", 1024, 1024},
		{"32KiB-1", 32767, 32767},
		{"32KiB", 32768, 32768},
		{"unlimited-64B", 64, math.MaxInt},
	} {
		b.Run(tt.name, func(b *testing.B) {
			input := strings.Repeat("x", tt.size)
			b.ReportAllocs()
			for i := 0; i < b.N; i++ {
				data, code := dfReadBounded(ctx, strings.NewReader(input), tt.max, tt.size)
				if code != "" || len(data) != tt.size {
					b.Fatal("read failed")
				}
				dfReadBenchmarkResult = data
			}
		})
	}
}

func BenchmarkCompressionDecompressBounded(b *testing.B) {
	ctx := RootExecution()
	data := Compress_Compress(ctx, NewBytes([]byte(strings.Repeat("x", 64))), "gzip", 6, None[int]())
	if data.Failed {
		b.Fatal("compress setup failed")
	}
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		result := Compress_Decompress(ctx, data.Val, "gzip", Some(64))
		if result.Failed || len(result.Val.Data) != 64 {
			b.Fatal("decompress failed")
		}
		dfReadBenchmarkResult = result.Val.Data
	}
}

func BenchmarkArchiveUnpackBounded(b *testing.B) {
	ctx := RootExecution()
	entries := NewList(&ArchiveEntry{Path: "file", Data: NewBytes([]byte(strings.Repeat("x", 64)))})
	data := Archive_Pack(ctx, entries, "tar", None[int]())
	if data.Failed {
		b.Fatal("pack setup failed")
	}
	limits := Some(&ArchiveLimits{MaxEntries: Some(1), MaxEntryBytes: Some(64), MaxTotalBytes: Some(64)})
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		result := Archive_Unpack(ctx, data.Val, "tar", limits)
		if result.Failed || len(result.Val.Items) != 1 || len(result.Val.Items[0].Data.Data) != 64 {
			b.Fatal("unpack failed")
		}
		dfReadBenchmarkResult = result.Val.Items[0].Data.Data
	}
}
