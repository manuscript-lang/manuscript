// Command golowerdev lowers a file with the typed lowerer and runs it. It is a
// development harness for the lowering rewrite.
package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"github.com/manuscript-lang/manuscript/pkg/golower"
)

func main() {
	file := os.Args[1]
	tests := len(os.Args) > 2 && os.Args[2] == "test"
	r := compiler.CompileFile(file, compiler.Options{AnalyzeOnly: true, Entry: !tests, Tests: tests})
	for _, d := range r.Diagnostics {
		fmt.Println(d)
	}
	if !r.Success() {
		os.Exit(1)
	}
	source, err := golower.Go(r.Program, filepath.Base(file), golower.Options{Entry: !tests, Tests: tests})
	if err != nil {
		fmt.Fprintln(os.Stderr, "lowering:", err)
		os.Exit(2)
	}
	dir := filepath.Join(".golowerdev", filepath.Base(file))
	os.MkdirAll(dir, 0o755)
	out := filepath.Join(dir, "main.go")
	os.WriteFile(out, []byte(source), 0o644)
	if len(os.Args) > 2 && os.Args[2] == "emit" {
		fmt.Println(source)
		return
	}
	cmd := exec.Command("go", "run", "./"+dir)
	cmd.Stdout, cmd.Stderr = os.Stdout, os.Stderr
	if err := cmd.Run(); err != nil {
		os.Exit(3)
	}
}

