// Command cgen compiles the numeric subset of a project to C (prototype).
//
//	go run ./scripts/cgen <ms.toml|file.ms> <out-dir>
//
// It writes kernels.c and entries.json and lists the functions it skipped.
package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"

	"github.com/manuscript-lang/manuscript/pkg/cbackend"
	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func main() {
	if len(os.Args) != 3 {
		fmt.Fprintln(os.Stderr, "usage: cgen <ms.toml|file.ms> <out-dir>")
		os.Exit(2)
	}
	result := compiler.CompileFile(os.Args[1], compiler.Options{})
	if !result.Success() {
		for _, d := range result.Diagnostics {
			fmt.Fprintln(os.Stderr, d)
		}
		os.Exit(1)
	}
	root := result.SourceRoot
	if os.Getenv("CGEN_DEBUG") != "" {
		for _, m := range result.Program.Modules {
			fmt.Fprintln(os.Stderr, "module", m.File, len(m.Declarations))
		}
		fmt.Fprintln(os.Stderr, "root", root)
	}
	out := cbackend.Generate(result.Program, "")
	if err := os.MkdirAll(os.Args[2], 0o755); err != nil {
		panic(err)
	}
	must(os.WriteFile(filepath.Join(os.Args[2], "kernels.c"), []byte(out.C), 0o644))
	data, _ := json.MarshalIndent(out.Entries, "", "  ")
	must(os.WriteFile(filepath.Join(os.Args[2], "entries.json"), data, 0o644))
	var names []string
	for name := range out.Skipped {
		names = append(names, name)
	}
	sort.Strings(names)
	for _, e := range out.Entries {
		fmt.Println("compiled", e.Name)
	}
	for _, name := range names {
		fmt.Println("skipped ", name+":", out.Skipped[name])
	}
}

func must(err error) {
	if err != nil {
		panic(err)
	}
}
