// Command stdgen regenerates the standard-library declarations in pkg/runtime
// (std_*_gen.go) from the Manuscript standard sources. Run it with `make stdgen`
// after changing a @std signature; the lowering package's freshness test fails
// while the checked-in files are stale.
package main

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/manuscript-lang/manuscript/pkg/lower"
)

func main() {
	dir := "pkg/runtime"
	if len(os.Args) > 1 {
		dir = os.Args[1]
	}
	files, err := lower.StandardRuntime()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	old, _ := filepath.Glob(filepath.Join(dir, "std_*_gen.go"))
	for _, f := range old {
		if err := os.Remove(f); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
	}
	for name, text := range files {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(text), 0o644); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
	}
}
