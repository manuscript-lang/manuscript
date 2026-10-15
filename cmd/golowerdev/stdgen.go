package main

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/manuscript-lang/manuscript/pkg/golower"
)

// `golowerdev stdgen DIR` writes the generated standard-runtime declarations
// and signature checks into DIR (pkg/rt).
func init() {
	if len(os.Args) > 2 && os.Args[1] == "stdgen" {
		files, err := golower.StandardRuntime()
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		old, _ := filepath.Glob(filepath.Join(os.Args[2], "std_*_gen.go"))
		for _, f := range old {
			os.Remove(f)
		}
		for name, text := range files {
			if err := os.WriteFile(filepath.Join(os.Args[2], name), []byte(text), 0o644); err != nil {
				fmt.Fprintln(os.Stderr, err)
				os.Exit(1)
			}
		}
		os.Exit(0)
	}
}
