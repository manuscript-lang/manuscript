package project_test

import (
	"fmt"
	"os"
	"path/filepath"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/project"
)

// BenchmarkDiscoverModules separates ordinary project discovery, the test-only
// negative control, and discovery with an unsaved source and test file.
func BenchmarkDiscoverModules(b *testing.B) {
	for _, size := range []int{128, 256, 512} {
		b.Run(fmt.Sprint(size), func(b *testing.B) {
			root := b.TempDir()
			p := project.Project{Root: root, Source: filepath.Join(root, "src")}
			for i := range size {
				for _, name := range []string{
					fmt.Sprintf("src/part%03d/value%04d.ms", i/16, i),
					fmt.Sprintf("src/part%03d/value%04d_test.ms", i/16, i),
					fmt.Sprintf("tests/part%03d/value%04d_test.ms", i/16, i),
					fmt.Sprintf("src/.hidden/value%04d_test.ms", i),
					fmt.Sprintf("vendor/value%04d_test.ms", i),
				} {
					path := filepath.Join(root, name)
					if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
						b.Fatal(err)
					}
					if err := os.WriteFile(path, nil, 0600); err != nil {
						b.Fatal(err)
					}
				}
			}
			for _, mode := range []string{"Source", "Tests", "Overlay", "SourceDirect", "TestsDirect"} {
				b.Run(mode, func(b *testing.B) {
					var overlay map[string]string
					want := size * 3
					includeSource := mode != "Tests" && mode != "TestsDirect"
					if !includeSource {
						want = size * 2
					}
					if mode == "Overlay" {
						overlay = map[string]string{
							filepath.Join(p.Source, "new.ms"):           "",
							filepath.Join(root, "tests", "new_test.ms"): "",
						}
						want += len(overlay)
					}
					b.ReportAllocs()
					b.ResetTimer()
					for range b.N {
						var files []string
						var err error
						if mode == "SourceDirect" || mode == "TestsDirect" {
							files, err = project.DiscoverModules(p, includeSource)
						} else {
							files, err = project.DiscoverModulesWithOverlay(p, includeSource, overlay)
						}
						if err != nil || len(files) != want {
							b.Fatalf("found %d files, want %d: %v", len(files), want, err)
						}
					}
				})
			}
		})
	}
}
