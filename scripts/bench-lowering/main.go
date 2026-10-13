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

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"github.com/manuscript-lang/manuscript/scripts/internal/devtool"
)

//go:embed workloads.ms workloads.go.txt program.ms harness.go.txt production.ms production.go.txt native-defaults.ms native-defaults.go.txt
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
	workloads := flag.Bool("workloads", false, "measure generated loops, calls, access, Game of Life and boxed-boundary controls against handwritten Go")
	production := flag.Bool("production", false, "benchmark primitive equality and callable cleanup in generated code")
	nativeDefaults := flag.Bool("native-defaults", false, "benchmark generated native defaults, including callable construction")
	baseline := flag.Bool("baseline", false, "spell defaulted arguments explicitly for a main-branch comparison")
	flag.Parse()
	program, harnessFile := "program.ms", "harness.go.txt"
	names := []string{"scalar", "calls", "items", "add"}
	if *workloads {
		program, harnessFile = "workloads.ms", "workloads.go.txt"
		names = []string{"scalar", "calls", "items", "add", "identity", "forwarded", "copied", "capture", "stored", "life", "matched", "ranged", "compare", "sort_values", "sort_captured"}
	}
	if *production {
		program, harnessFile = "production.ms", "production.go.txt"
		names = []string{"empty", "kept", "ints", "floats", "bools", "strings"}
	}
	if *nativeDefaults {
		program, harnessFile = "native-defaults.ms", "native-defaults.go.txt"
		names = []string{"direct_explicit", "direct_omitted", "bound_explicit", "bound_omitted", "encode_bind", "csv_explicit", "csv_omitted", "command_explicit", "command_omitted", "command_bind"}
		names = append(names, "filesystem_setup", "filesystem_explicit", "filesystem_omitted", "filesystem_bind")
	}
	source, err := inputs.ReadFile(program)
	if err != nil {
		return err
	}
	if *nativeDefaults && *baseline {
		source = []byte(strings.NewReplacer(
			"base64_encode(data)", "base64_encode(data, false)",
			"encode(data)", "encode(data, false)",
			"CsvOptions()", "CsvOptions(\",\", \"\\n\")",
			"arguments: [])", "arguments: [], input: \"\".to_bytes())",
			"fs.write_file(\"\", data)", "fs.write_file(\"\", data, false)",
		).Replace(string(source)))
	}
	result := compiler.CompileSource("benchmark.ms", string(source), compiler.Options{})
	if !result.Success() {
		return fmt.Errorf("benchmark source: %v", result.Diagnostics)
	}
	template, err := inputs.ReadFile(harnessFile)
	if err != nil {
		return err
	}
	var replacements []string
	if *workloads {
		constructor := "&rt.List{Type: \"@std/List[Int]\", Items: boxedValues}"
		if strings.Contains(result.Source, "rt.NewList(") {
			constructor = "rt.NewList(\"@std/List[Int]\", boxedValues)"
		}
		replacements = append(replacements, "@@listConstructor@@", constructor)
		sortConstructor := "&rt.List{Type: \"@std/List[Int]\", Items: source}"
		if strings.Contains(result.Source, "rt.NewList(") {
			sortConstructor = "rt.NewList(\"@std/List[Int]\",source)"
		}
		replacements = append(replacements, "@@sortConstructor@@", sortConstructor)
	}
	if *nativeDefaults {
		replacements = append(replacements, "@@baseline@@", strconv.FormatBool(*baseline))
	}
	for _, name := range names {
		symbol := result.Program.Symbols["benchmark.ms"][name]
		replacements = append(replacements, "@@"+name+"@@", symbol.ID, "@@"+name+"Position@@", strconv.Quote(symbol.Decl.Result.Pos.String()))
	}
	if *production {
		replacements = append(replacements, "@@Resource@@", strconv.Quote(checker.TypeKey(result.Program.Symbols["benchmark.ms"]["Resource"].Type)))
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
	fmt.Println("Generated source and benchmark harness:", directory)
	arguments := []string{"test", "-mod=vendor", "-run", "^TestBenchmarkParity$", "-bench", "^Benchmark(Lowering|Workloads)$", "-benchmem", "-benchtime=" + *benchtime, "-count=" + strconv.Itoa(*count)}
	if !*nativeDefaults {
		arguments = append(arguments, "-tags=ms_lean")
	} else {
		arguments = append(arguments, "-cpu=1")
	}
	command := exec.Command(devtool.Go(), append(arguments, directory)...)
	command.Stdout, command.Stderr = os.Stdout, os.Stderr
	return command.Run()
}
