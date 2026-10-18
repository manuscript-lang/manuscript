// bench-lists measures generated numeric List operations using the bundled SDK.
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

	"github.com/manuscript-lang/manuscript/internal/devtool"
	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

//go:embed program.ms harness.go.txt prototype.go.txt
var inputs embed.FS

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func run() error {
	output := flag.String("output", ".artifacts/list-bench", "generated source, benchmark binary and samples")
	count := flag.Int("count", 3, "benchmark repetitions")
	benchtime := flag.String("benchtime", "200ms", "time per benchmark")
	bench := flag.String("bench", "BenchmarkLists", "benchmark selection")
	flag.Parse()
	if *count < 1 {
		return fmt.Errorf("count must be positive")
	}
	source, err := inputs.ReadFile("program.ms")
	if err != nil {
		return err
	}
	result := compiler.CompileSource("list-benchmark.ms", string(source), compiler.Options{})
	if !result.Success() {
		return fmt.Errorf("benchmark source: %v", result.Diagnostics)
	}
	var replacements []string
	for _, name := range []string{"build", "index", "iterate", "callbacks", "sorted", "compare", "callback_write"} {
		symbol := result.Program.Symbol("list-benchmark.ms", name)
		replacements = append(replacements, "@@"+name+"@@", symbol.ID)
	}
	directory, err := filepath.Abs(*output)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(directory, 0755); err != nil {
		return err
	}
	files := map[string][]byte{"program.go": []byte(result.Source), "program.ms": source}
	for _, name := range []string{"harness", "prototype"} {
		template, err := inputs.ReadFile(name + ".go.txt")
		if err != nil {
			return err
		}
		data, err := format.Source([]byte(strings.NewReplacer(replacements...).Replace(string(template))))
		if err != nil {
			return fmt.Errorf("%s: %w", name, err)
		}
		files[name+"_test.go"] = data
	}
	for name, data := range files {
		if err := os.WriteFile(filepath.Join(directory, name), data, 0644); err != nil {
			return err
		}
	}
	command := exec.Command(devtool.Go(), "test", "-mod=vendor", "-c", "-o", filepath.Join(directory, "lists.test"), directory)
	command.Stdout, command.Stderr = os.Stdout, os.Stderr
	if err := command.Run(); err != nil {
		return err
	}
	command = exec.Command(filepath.Join(directory, "lists.test"), "-test.run=^TestList", "-test.bench="+*bench, "-test.benchmem", "-test.benchtime="+*benchtime, "-test.count="+strconv.Itoa(*count))
	command.Stdout, command.Stderr = os.Stdout, os.Stderr
	return command.Run()
}
