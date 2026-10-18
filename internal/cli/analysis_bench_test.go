package cli

import (
	"fmt"
	"os"
	"path/filepath"
	"testing"
)

// BenchmarkAnalysisProject measures CLI selection and checking in process;
// stdout encoding, cold standard loading and native process startup are excluded.
func BenchmarkAnalysisProject(b *testing.B) {
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
			for i := range size {
				path := filepath.Join(src, fmt.Sprintf("part%04d.ms", i))
				if err := os.WriteFile(path, []byte("export fn value() Int: return 1\n"), 0600); err != nil {
					b.Fatal(err)
				}
			}
			for _, command := range []string{"check", "lint"} {
				b.Run(command, func(b *testing.B) {
					selection, err := selectAnalysisInputs([]string{manifest})
					if err != nil {
						b.Fatal(err)
					}
					if _, issues := analyzeSelection(command, selection); len(issues) != 0 {
						b.Fatal(issues)
					}
					b.ReportAllocs()
					b.ResetTimer()
					for range b.N {
						selection, err := selectAnalysisInputs([]string{manifest})
						if err != nil {
							b.Fatal(err)
						}
						inputs, issues := analyzeSelection(command, selection)
						if len(issues) != 0 || len(inputs) != 1 {
							b.Fatalf("invalid analysis: %d inputs, %v", len(inputs), issues)
						}
						if command == "lint" {
							lintFindings(inputs[0].result)
						}
					}
				})
			}
		})
	}
}
