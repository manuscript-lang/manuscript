package msruntime

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func BenchmarkFileInfoConstruction(b *testing.B) {
	path := filepath.Join(b.TempDir(), "entry")
	if err := os.WriteFile(path, []byte("metadata"), 0600); err != nil {
		b.Fatal(err)
	}
	info, err := os.Stat(path)
	if err != nil {
		b.Fatal(err)
	}
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		got := fileInfoOf(info, time.Time{})
		if got.Size != 8 || got.Exact.Len() != 14 {
			b.Fatal("invalid file info")
		}
	}
}

func BenchmarkFileSystemStat(b *testing.B) {
	path := filepath.Join(b.TempDir(), "entry")
	if err := os.WriteFile(path, []byte("metadata"), 0600); err != nil {
		b.Fatal(err)
	}
	fs := &osFileSystem{}
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		got := fs.Stat(tctx, path, true)
		if got.Failed || got.Val.Size != 8 || got.Val.Exact.Len() != 14 {
			b.Fatal("invalid stat")
		}
	}
}
