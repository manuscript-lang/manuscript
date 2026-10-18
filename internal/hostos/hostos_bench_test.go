package hostos

import (
	"os"
	"testing"
)

var hostStatResult Stat
var hostUsageResult Usage
var hostCountResult int
var hostFSResult FileSystemInfo

// StatInfo converts a FileInfo snapshot; the other cases query live OS metadata.
func BenchmarkHostMetadata(b *testing.B) {
	file, err := os.CreateTemp(b.TempDir(), "metadata")
	if err != nil {
		b.Fatal(err)
	}
	b.Cleanup(func() { _ = file.Close() })
	info, err := file.Stat()
	if err != nil {
		b.Fatal(err)
	}
	b.Run("StatInfo", func(b *testing.B) {
		b.ReportAllocs()
		for i := 0; i < b.N; i++ {
			hostStatResult = StatInfo(info)
		}
	})
	b.Run("ResourceUsage", func(b *testing.B) {
		b.ReportAllocs()
		for i := 0; i < b.N; i++ {
			hostUsageResult, err = ResourceUsage()
			if err != nil {
				b.Fatal(err)
			}
		}
	})
	b.Run("AvailableParallelism", func(b *testing.B) {
		b.ReportAllocs()
		for i := 0; i < b.N; i++ {
			hostCountResult, err = AvailableParallelism()
			if err != nil {
				b.Fatal(err)
			}
		}
	})
	b.Run("StatFS", func(b *testing.B) {
		b.ReportAllocs()
		for i := 0; i < b.N; i++ {
			hostFSResult, err = StatFS(file.Name())
			if err != nil {
				b.Fatal(err)
			}
		}
	})
}
