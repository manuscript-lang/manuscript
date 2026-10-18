package compiler_test

import (
	"fmt"
	"os"
	"path/filepath"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"github.com/manuscript-lang/manuscript/pkg/frontend"
)

// BenchmarkProjectPipeline includes repeated imports of a shared leaf and
// unimported project modules. Checker standard declarations are warmed first;
// process startup and native Go compilation are deliberately excluded.
func BenchmarkProjectPipeline(b *testing.B) {
	for _, size := range []int{128, 256, 512} {
		b.Run(fmt.Sprint(size), func(b *testing.B) {
			root := b.TempDir()
			src := filepath.Join(root, "src")
			if err := os.Mkdir(src, 0700); err != nil {
				b.Fatal(err)
			}
			manifest := filepath.Join(root, "ms.toml")
			if err := os.WriteFile(manifest, []byte("[project]\nname = \"bench\"\nsource = \"src\"\n"), 0600); err != nil {
				b.Fatal(err)
			}
			if err := os.WriteFile(filepath.Join(src, "shared.ms"), []byte("export fn value() Int: return 1\n"), 0600); err != nil {
				b.Fatal(err)
			}
			for i := range size {
				name := filepath.Join(src, fmt.Sprintf("part%04d.ms", i))
				source := "import value from \"./shared.ms\"\nexport fn result() Int: return value()\n"
				if err := os.WriteFile(name, []byte(source), 0600); err != nil {
					b.Fatal(err)
				}
			}
			for _, mode := range []string{"Load", "Check", "Lower"} {
				b.Run(mode, func(b *testing.B) {
					options := compiler.Options{AnalyzeOnly: mode == "Check", Tests: true}
					check := compiler.CompileFile(manifest, compiler.Options{AnalyzeOnly: true})
					if !check.Success() {
						b.Fatal(check.Diagnostics)
					}
					b.ReportAllocs()
					b.ResetTimer()
					for range b.N {
						if mode == "Load" {
							graph := frontend.LoadFile(manifest, frontend.Options{})
							if len(graph.Diagnostics) != 0 || len(graph.Modules) != size+1 {
								b.Fatalf("invalid graph: %d modules, %v", len(graph.Modules), graph.Diagnostics)
							}
						} else {
							result := compiler.CompileFile(manifest, options)
							if !result.Success() || mode == "Lower" && result.Source == "" {
								b.Fatalf("invalid result: %v", result.Diagnostics)
							}
						}
					}
				})
			}
		})
	}
}
