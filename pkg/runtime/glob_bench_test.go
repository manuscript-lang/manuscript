package msruntime

import (
	"fmt"
	"os"
	"path/filepath"
	"testing"
)

func BenchmarkFileSystemGlob(b *testing.B) {
	root := b.TempDir()
	for i := range 200 {
		name := filepath.Join(root, fmt.Sprintf("file-%03d.txt", i))
		if err := os.WriteFile(name, nil, 0600); err != nil {
			b.Fatal(err)
		}
	}
	ctx := RootExecution()
	fs := &osFileSystem{directory: root}
	for _, pattern := range []string{"*.txt", "*.{txt,md,json}", "@(file|note)-*.{txt,md,json}"} {
		b.Run(pattern, func(b *testing.B) {
			b.Run("Glob", func(b *testing.B) {
				b.ReportAllocs()
				for b.Loop() {
					result := fs.Glob(ctx, ".", pattern, None[int]())
					if result.Failed || len(result.Val.Items) != 200 {
						b.Fatal(result)
					}
				}
			})
			b.Run("GlobEntries", func(b *testing.B) {
				options := &GlobOptions{Patterns: NewList(pattern), Exclude: NewList[string]()}
				b.ReportAllocs()
				for b.Loop() {
					result := fs.GlobEntries(ctx, ".", options, None[func(*Execution, *PathEntry) bool]())
					if result.Failed || len(result.Val.Items) != 200 {
						b.Fatal(result)
					}
				}
			})
		})
	}
}

func BenchmarkPathMatchesGlob(b *testing.B) {
	ctx := RootExecution()
	p := Path_Posix(ctx)
	for _, pattern := range []string{"**/*.txt", "**/*.{txt,md,json}", "**/@(file|note)-*.{txt,md,json}"} {
		b.Run(pattern, func(b *testing.B) {
			b.ReportAllocs()
			for b.Loop() {
				result := p.MatchesGlob(ctx, "notes/file-001.txt", pattern)
				if result.Failed || !result.Val {
					b.Fatal(result)
				}
			}
		})
	}
}
