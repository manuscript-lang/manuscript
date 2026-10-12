// ms checks, compiles, and runs Manuscript modules and project manifests.
package main

import (
	"encoding/json"
	"fmt"
	"github.com/manuscript-lang/manuscript/compiler"
	"github.com/manuscript-lang/manuscript/syntax"
	"github.com/manuscript-lang/manuscript/tooling"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
)

const help = `Usage: ms <check|build|emit|run|test|fmt|inspect|diagram|lock|doc> <file.ms|ms.toml> [-o output] [-- program arguments]

check  Parse and type-check without executing source
build  Build a native executable (default: ./program)
emit   Emit a self-contained Go program (-o writes a file)
run    Build and run an exported main(process: Process) -> Int
test   Build and execute module test blocks, including imported modules
fmt    Format a module; --check verifies without writing
inspect Emit checked symbols, source hashes, call sites, and statement spans as JSON
diagram Emit the checked static call graph as Mermaid
doc    Generate public module docs or the bundled stdlib reference (ms doc --help)
lock   Explicitly pin the compiler/runtime, Go toolchain, and target in ms.lock

The Go toolchain is required for build, run, and test.
Set MANUSCRIPT_GO to select its executable.
`

func main() { os.Exit(run(os.Args[1:])) }
func run(args []string) int {
	if len(args) == 0 || args[0] == "--help" || args[0] == "-h" {
		fmt.Print(help)
		return 0
	}
	if args[0] == "--version" {
		fmt.Println("Manuscript 0.1.0")
		return 0
	}
	if args[0] == "doc" {
		return runDoc(args[1:])
	}
	if len(args) < 2 {
		fmt.Fprint(os.Stderr, help)
		return 2
	}
	command, filename := args[0], args[1]
	output := ""
	formatCheck, structured, debug := false, false, false
	var arguments []string
	for i := 2; i < len(args); i++ {
		if args[i] == "--" {
			arguments = args[i+1:]
			break
		}
		if args[i] == "--debug" {
			debug = true
			continue
		}
		if args[i] == "--check" {
			formatCheck = true
			continue
		}
		if args[i] == "--json" {
			structured = true
			continue
		}
		if args[i] == "-o" || args[i] == "--output" {
			i++
			if i == len(args) {
				fmt.Fprintln(os.Stderr, "output flag requires a path")
				return 2
			}
			output = args[i]
		} else {
			fmt.Fprintln(os.Stderr, "unknown option:", args[i])
			return 2
		}
	}
	if !strings.Contains("|check|build|emit|run|test|fmt|inspect|diagram|lock|", "|"+command+"|") {
		fmt.Fprintln(os.Stderr, "unknown command:", command)
		return 2
	}
	if formatCheck && command != "fmt" || structured && command != "check" || debug && command != "build" && command != "run" && command != "test" {
		fmt.Fprintln(os.Stderr, "flag is not valid for this command")
		return 2
	}
	if command == "fmt" {
		source, err := os.ReadFile(filename)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 1
		}
		formatted, err := tooling.Format(filename, string(source))
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 1
		}
		if string(source) == formatted {
			return 0
		}
		if formatCheck {
			fmt.Fprintln(os.Stderr, "Formatting needed:", filename)
			return 1
		}
		info, err := os.Stat(filename)
		if err == nil {
			err = tooling.WriteFormatted(filename, formatted, info.Mode().Perm())
		}
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 1
		}
		return 0
	}

	options := compiler.Options{Tests: command == "test", Entry: command == "build" || command == "run"}
	result := compiler.CompileFile(filename, options)
	if structured {
		if result.Diagnostics == nil {
			result.Diagnostics = []syntax.Diagnostic{}
		}
		data, err := json.MarshalIndent(struct {
			Format      int                 `json:"format"`
			Diagnostics []syntax.Diagnostic `json:"diagnostics"`
		}{1, result.Diagnostics}, "", "  ")
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 1
		}
		fmt.Println(string(data))
		if !result.Success() {
			return 1
		}
		return 0
	}
	if !result.Success() {
		for _, d := range result.Diagnostics {
			fmt.Fprintln(os.Stderr, d)
		}
		return 1
	}
	switch command {
	case "lock":
		if result.ProjectRoot == "" {
			fmt.Fprintln(os.Stderr, "lock requires a project ms.toml")
			return 2
		}
		if err := compiler.WritePin(result.ProjectRoot); err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 1
		}
		fmt.Println("Pinned", filename)
		return 0
	case "inspect", "diagram":
		inspection := tooling.Inspect(result.Program)
		var source string
		if command == "diagram" {
			source = tooling.Diagram(inspection)
		} else {
			data, err := json.MarshalIndent(inspection, "", "  ")
			if err != nil {
				fmt.Fprintln(os.Stderr, err)
				return 1
			}
			source = string(data) + "\n"
		}
		if output == "" {
			fmt.Print(source)
		} else if err := os.WriteFile(output, []byte(source), 0644); err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 1
		}
		return 0
	case "check":
		fmt.Println("Checked", filename)
		return 0
	case "emit":
		source, err := compiler.Standalone(result.Source)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 1
		}
		if output == "" {
			fmt.Print(source)
		} else if err := os.WriteFile(output, []byte(source), 0644); err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 1
		}
		return 0
	case "build":
		if output == "" {
			output = "program"
		}
		absolute, err := filepath.Abs(output)
		if err == nil {
			cache := filepath.Join(filepath.Dir(absolute), ".ms-cache")
			if result.ProjectRoot != "" {
				cache = filepath.Join(result.ProjectRoot, ".ms-cache")
			}
			_, err = compiler.BuildChecked(result, absolute, cache, debug)
		}
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 1
		}
		fmt.Println("Built", output)
		return 0
	default:
		directory, err := os.MkdirTemp("", "manuscript-run-")
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 1
		}
		defer os.RemoveAll(directory)
		executable := filepath.Join(directory, "program")
		cache := ""
		if result.ProjectRoot != "" {
			cache = filepath.Join(result.ProjectRoot, ".ms-cache")
		}
		if _, err := compiler.BuildChecked(result, executable, cache, debug); err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 1
		}
		child := exec.Command(executable, arguments...)
		child.Stdin = os.Stdin
		child.Stdout = os.Stdout
		child.Stderr = os.Stderr
		if err := runWithSignals(child); err != nil {
			if exit, ok := err.(*exec.ExitError); ok {
				return exit.ExitCode()
			}
			fmt.Fprintln(os.Stderr, err)
			return 1
		}
		return 0
	}
}

// Keep the launcher alive until the native host completes cancellation and cleanup.
func runWithSignals(child *exec.Cmd) error {
	stops := make(chan os.Signal, 2)
	signal.Notify(stops, os.Interrupt, syscall.SIGTERM)
	defer signal.Stop(stops)
	if err := child.Start(); err != nil {
		return err
	}
	done := make(chan struct{})
	defer close(done)
	go func() {
		for {
			select {
			case stop := <-stops:
				_ = child.Process.Signal(stop)
			case <-done:
				return
			}
		}
	}()
	return child.Wait()
}
