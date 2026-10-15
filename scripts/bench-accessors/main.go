// bench-accessors retains emitted Go, native parity tests, escape analysis and samples.
package main

import (
	"bytes"
	"crypto/sha256"
	"embed"
	"encoding/json"
	"flag"
	"fmt"
	"go/ast"
	"go/format"
	"go/parser"
	"go/token"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"strconv"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

//go:embed program.ms harness.go.txt
var inputs embed.FS

var names = []string{"list_length", "map_length", "set_length", "list_empty", "string_bytes", "string_length", "list_first", "list_last", "map_empty", "set_empty", "bytes_empty", "string_empty", "string_scalars", "bytes_length", "optional_some", "optional_none", "result_ok", "result_error", "float_nan", "float_finite", "method_control", "source_direct", "source_view", "source_generic", "guard_length", "metadata_status", "typed_optional", "typed_result", "duration_seconds", "string_alternating", "logger_level"}

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
func run() error {
	output := flag.String("output", ".artifacts/accessor-bench", "retained source, native test binary and samples")
	revision := flag.String("revision", "working-tree", "compiler revision or worktree description for retained metadata")
	legacy := flag.Bool("legacy", false, "use method syntax with the unmodified baseline compiler/runtime")
	generateOnly := flag.Bool("generate-only", false, "retain source and harness without native compilation")
	goTool := flag.String("go", "toolchain/go/bin/go", "same pinned SDK for both revisions")
	count := flag.Int("count", 5, "native benchmark repetitions")
	benchtime := flag.String("benchtime", "200ms", "time per native benchmark")
	bench := flag.String("bench", "^BenchmarkAccessor", "native benchmark selection")
	flag.Parse()
	if *count < 1 {
		return fmt.Errorf("count must be positive")
	}
	source, err := inputs.ReadFile("program.ms")
	if err != nil {
		return err
	}
	if *legacy {
		read := regexp.MustCompile(`\.(length|is_empty|first|last|byte_length|scalar_length|is_some|is_none|is_ok|is_error|is_nan|is_finite|metadata|observed|level)\b`)
		source = read.ReplaceAll(source, []byte(".${1}()"))
		source = []byte(strings.NewReplacer("get observed -> Int", "fn observed() -> Int", "guard.value", "guard.get()", "span.seconds", "span.to_seconds()").Replace(string(source)))
	}
	result := compiler.CompileSource("accessor-benchmark.ms", string(source), compiler.Options{})
	if !result.Success() {
		return fmt.Errorf("benchmark source: %v", result.Diagnostics)
	}
	template, err := inputs.ReadFile("harness.go.txt")
	if err != nil {
		return err
	}
	var replacements []string
	symbols := map[string]string{}
	for _, name := range names {
		symbol := result.Program.Symbol("accessor-benchmark.ms", name).ID
		symbols[name] = symbol
		replacements = append(replacements, "@@"+name+"@@", symbol)
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
	for name, data := range map[string][]byte{"program.ms": source, "program.go": []byte(result.Source), "program_test.go": harness} {
		if err := os.WriteFile(filepath.Join(directory, name), data, 0644); err != nil {
			return err
		}
	}
	emission, err := emissionInventory(result.Source, symbols, *legacy)
	if err != nil {
		return err
	}
	if err := os.WriteFile(filepath.Join(directory, "emission.json"), emission, 0644); err != nil {
		return err
	}
	goVersion, err := exec.Command(*goTool, "version").Output()
	if err != nil {
		return err
	}
	environment := map[string]string{}
	for _, key := range []string{"GOMAXPROCS", "GOGC", "GOMEMLIMIT", "GOCACHE", "XDG_CACHE_HOME", "GOPATH", "GOFLAGS"} {
		environment[key] = os.Getenv(key)
	}
	metadata, err := json.MarshalIndent(map[string]any{"revision": *revision, "legacy": *legacy, "go": strings.TrimSpace(string(goVersion)), "goos": runtime.GOOS, "goarch": runtime.GOARCH, "source_sha256": fmt.Sprintf("%x", sha256.Sum256(source)), "emitted_go_sha256": fmt.Sprintf("%x", sha256.Sum256([]byte(result.Source))), "environment": environment, "reads_per_operation": 1024, "samples": *count, "benchtime": *benchtime, "native_cpus": 1}, "", "  ")
	if err != nil {
		return err
	}
	if err := os.WriteFile(filepath.Join(directory, "metadata.json"), metadata, 0644); err != nil {
		return err
	}
	if *generateOnly {
		fmt.Println("Generated:", directory)
		return nil
	}
	binary := filepath.Join(directory, "accessors.test")
	command := exec.Command(*goTool, "test", "-mod=vendor", "-buildvcs=false", "-tags=ms_lean", "-gcflags=-m=2", "-c", "-o", binary, directory)
	var buildOutput bytes.Buffer
	command.Stdout, command.Stderr = &buildOutput, &buildOutput
	buildErr := command.Run()
	if err := os.WriteFile(filepath.Join(directory, "escape.txt"), buildOutput.Bytes(), 0644); err != nil {
		return err
	}
	if buildErr != nil {
		return fmt.Errorf("native benchmark build: %w\n%s", buildErr, buildOutput.Bytes())
	}
	command = exec.Command(binary, "-test.run=^TestAccessor", "-test.bench="+*bench, "-test.benchmem", "-test.benchtime="+*benchtime, "-test.count="+strconv.Itoa(*count), "-test.cpu=1")
	samples, runErr := command.CombinedOutput()
	fmt.Print(string(samples))
	if err := os.WriteFile(filepath.Join(directory, "samples.txt"), samples, 0644); err != nil {
		return err
	}
	return runErr
}

// Inspect each concrete workload body, excluding initialization wrappers and
// unrelated methods used in other workloads. The current baseline partition is
// recorded from emitted Go rather than fixed to a historical audit or inferred
// from surface syntax.
func emissionInventory(source string, symbols map[string]string, legacy bool) ([]byte, error) {
	tree, err := parser.ParseFile(token.NewFileSet(), "program.go", source, 0)
	if err != nil {
		return nil, err
	}
	bodies := map[string]*ast.BlockStmt{}
	for _, declaration := range tree.Decls {
		if fn, ok := declaration.(*ast.FuncDecl); ok {
			bodies[fn.Name.Name] = fn.Body
		}
	}
	type entry struct {
		Class string
		Calls map[string]int
	}
	entries := map[string]entry{}
	partition := map[string]int{}
	for _, name := range names[:20] {
		body := bodies["call_"+symbols[name]]
		if body == nil {
			return nil, fmt.Errorf("no direct body for %s", name)
		}
		calls := map[string]int{}
		ast.Inspect(body, func(node ast.Node) bool {
			call, ok := node.(*ast.CallExpr)
			if !ok {
				return true
			}
			selector, ok := call.Fun.(*ast.SelectorExpr)
			if !ok {
				return true
			}
			receiver, ok := selector.X.(*ast.Ident)
			if ok && receiver.Name == "rt" {
				calls[selector.Sel.Name]++
			}
			return true
		})
		class := "direct"
		if calls["CallNative"] > 0 {
			class = "hoisted"
		}
		if calls["NativeMemberResult"] > 0 {
			class = "bound"
		}
		if !legacy {
			for _, forbidden := range []string{"NativeMemberResult", "Invoke", "Bind", "NewFunction", "BindNativeCall", "CallNative", "ReadAccessor"} {
				if calls[forbidden] != 0 {
					return nil, fmt.Errorf("static accessor %s emitted %s", name, forbidden)
				}
			}
		}
		entries[name] = entry{class, calls}
		partition[class]++
	}
	return json.MarshalIndent(struct {
		Legacy     bool
		Partition  map[string]int
		Candidates map[string]entry
	}{legacy, partition, entries}, "", "  ")
}
