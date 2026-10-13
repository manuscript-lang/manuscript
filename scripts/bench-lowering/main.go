// bench-lowering retains generated Go beside a handwritten typed-local benchmark.
// Run from the checkout root with the pinned SDK; no native compiler path changes.
package main

import (
	"embed"
	"flag"
	"fmt"
	"go/format"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"github.com/manuscript-lang/manuscript/scripts/internal/devtool"
)

//go:embed program.ms harness.go.txt
var inputs embed.FS

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
func run() error {
	output := flag.String("output", ".artifacts/lowering-bench", "directory for generated code and benchmark harness")
	count := flag.Int("count", 5, "benchmark repetitions")
	benchtime := flag.String("benchtime", "1s", "time per benchmark")
	flag.Parse()
	source, err := inputs.ReadFile("program.ms")
	if err != nil {
		return err
	}
	result := compiler.CompileSource("benchmark.ms", string(source), compiler.Options{})
	if !result.Success() {
		return fmt.Errorf("benchmark source: %v", result.Diagnostics)
	}
	template, err := inputs.ReadFile("harness.go.txt")
	if err != nil {
		return err
	}
	var replacements []string
	for _, name := range []string{"scalar", "calls", "items", "add"} {
		symbol := result.Program.Symbols["benchmark.ms"][name]
		replacements = append(replacements, "@@"+name+"@@", symbol.ID, "@@"+name+"Position@@", strconv.Quote(symbol.Decl.Result.Pos.String()))
	}
	harness, err := format.Source([]byte(strings.NewReplacer(replacements...).Replace(string(template))))
	if err != nil {
		return fmt.Errorf("benchmark harness: %w", err)
	}
	directory, err := filepath.Abs(*output)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(directory, 0755); err != nil {
		return err
	}
	for name, data := range map[string][]byte{"program.go": []byte(result.Source), "program_test.go": harness} {
		if err := os.WriteFile(filepath.Join(directory, name), data, 0644); err != nil {
			return err
		}
	}
	fmt.Println("Generated source and handwritten comparison:", directory)
	command := exec.Command(devtool.Go(), "test", "-mod=vendor", "-tags=ms_lean", "-run", "^TestBenchmarkParity$", "-bench", "^BenchmarkLowering$", "-benchmem", "-benchtime="+*benchtime, "-count="+strconv.Itoa(*count), directory)
	command.Stdout, command.Stderr = os.Stdout, os.Stderr
	return command.Run()
}
