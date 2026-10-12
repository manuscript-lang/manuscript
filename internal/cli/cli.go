// Package cli implements Manuscript command orchestration.
package cli

import (
	"encoding/json"
	"fmt"
	support "github.com/manuscript-lang/manuscript"
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"github.com/manuscript-lang/manuscript/pkg/stdlib"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
	"github.com/manuscript-lang/manuscript/pkg/tooling"
	"github.com/manuscript-lang/manuscript/pkg/tooling/lsp"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"runtime"
	"syscall"
)

// Run executes a command and returns its process exit status.
func Run(args []string) int {
	if len(args) == 0 || args[0] == "--help" || args[0] == "-h" {
		fmt.Print(help)
		return 0
	}
	if args[0] == "--version" {
		fmt.Println("Manuscript " + support.Version())
		return 0
	}
	usage, known := commandHelp(args[0])
	if !known {
		fmt.Fprintln(os.Stderr, "unknown command:", args[0])
		fmt.Fprintln(os.Stderr, "Run 'ms --help' to list commands.")
		return 2
	}
	if requestsHelp(args[1:]) {
		fmt.Print(usage)
		return 0
	}
	if args[0] == "help" {
		return runHelp(args[1:])
	}
	if args[0] == "doc" {
		return runDoc(args[1:])
	}
	if args[0] == "lsp" {
		if err := lsp.Serve(os.Stdin, os.Stdout); err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 1
		}
		return 0
	}
	if len(args) < 2 {
		fmt.Fprint(os.Stderr, usage)
		return 2
	}
	if args[0] == "stdlib" {
		if len(args) != 2 {
			fmt.Fprintln(os.Stderr, "usage: ms stdlib <directory>")
			return 2
		}
		if err := stdlib.Materialize(args[1]); err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 1
		}
		return 0
	}
	command, filename := args[0], args[1]
	output := ""
	cpuProfile, heapProfile, tracePath := "", "", ""
	formatCheck, structured, debug, watch := false, false, false, false
	buildTypeName := ""
	buildTypeSet := false
	var arguments []string
	for i := 2; i < len(args); i++ {
		switch args[i] {
		case "--":
			arguments = args[i+1:]
			i = len(args)
		case "--debug":
			debug = true
		case "--watch":
			watch = true
		case "--build-type":
			i++
			if i == len(args) || args[i] == "" {
				fmt.Fprintln(os.Stderr, "--build-type requires a build type")
				return 2
			}
			if buildTypeSet {
				fmt.Fprintln(os.Stderr, "--build-type may only be specified once")
				return 2
			}
			buildTypeName, buildTypeSet = args[i], true
		case "--check":
			formatCheck = true
		case "--json":
			structured = true
		case "-o", "--output", "--cpu-profile", "--heap-profile", "--trace":
			flag := args[i]
			i++
			if i == len(args) {
				message := "profile flag requires a path"
				if flag == "-o" || flag == "--output" {
					message = "output flag requires a path"
				}
				fmt.Fprintln(os.Stderr, message)
				return 2
			}
			switch flag {
			case "-o", "--output":
				output = args[i]
			case "--cpu-profile":
				cpuProfile = args[i]
			case "--heap-profile":
				heapProfile = args[i]
			case "--trace":
				tracePath = args[i]
			}
		default:
			fmt.Fprintln(os.Stderr, "unknown option:", args[i])
			return 2
		}
	}
	options := compiler.Options{}
	switch command {
	case "fmt": // Formatting returns before the compiler pipeline.
	case "check", "lint", "inspect", "diagram", "lock":
		options.AnalyzeOnly = true
		options.Entry = command != "lint" && filepath.Base(filename) == "ms.toml"
	case "emit": // Only source emission needs lowering without an entry launcher.
	case "build", "run", "debug", "profile":
		options.Entry = true
	case "test":
		options.Tests = true
	default:
		fmt.Fprintln(os.Stderr, "unknown command:", command)
		return 2
	}
	if watch && command != "run" && command != "test" {
		fmt.Fprintln(os.Stderr, "--watch requires run or test")
		return 2
	}
	if formatCheck && command != "fmt" || structured && command != "check" && command != "lint" || debug && command != "build" && command != "run" && command != "test" {
		fmt.Fprintln(os.Stderr, "flag is not valid for this command")
		return 2
	}
	kind, err := compiler.ParseBuildType(buildTypeName)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 2
	}
	if buildTypeSet && command != "build" && command != "run" && command != "test" && command != "debug" && command != "profile" {
		fmt.Fprintln(os.Stderr, "--build-type requires build, run, test, debug, or profile")
		return 2
	}
	if debug || command == "debug" {
		if buildTypeSet && kind != compiler.Debug {
			fmt.Fprintln(os.Stderr, "debug requires build type Debug")
			return 2
		}
		kind = compiler.Debug
	} else if command == "profile" && !buildTypeSet {
		kind = compiler.RelWithDebInfo
	}
	if (cpuProfile != "" || heapProfile != "" || tracePath != "") && command != "run" {
		fmt.Fprintln(os.Stderr, "profiling flags require run")
		return 2
	}
	if watch && (cpuProfile != "" || heapProfile != "" || tracePath != "") {
		fmt.Fprintln(os.Stderr, "--watch cannot be combined with profiling flags")
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

	if command == "profile" {
		if output == "" {
			output = "profile"
		}
		absolute, err := filepath.Abs(output)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 1
		}
		output = absolute
		cpuProfile = filepath.Join(output, "cpu.pprof")
		heapProfile = filepath.Join(output, "heap.pprof")
		tracePath = filepath.Join(output, "trace.out")
	}

	options.CPUProfile, options.HeapProfile, options.Trace = cpuProfile, heapProfile, tracePath

	switch command {
	case "build", "run", "test", "debug", "profile":
		// Native commands need the build pin; query the toolchain and hash
		// embedded inputs while the source is parsed and checked.
		go compiler.CurrentPin()
	}
	if watch {
		return watchProgram(command, filename, options, kind, "", arguments)
	}
	result := compiler.CompileFile(filename, options)
	if structured && command == "check" {
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
		return reportDiagnostics(result)
	}
	if command == "profile" {
		if err := os.Mkdir(output, 0700); err != nil {
			fmt.Fprintln(os.Stderr, "profile directory must be new:", err)
			return 1
		}
	}

	cache := ""
	if result.ProjectRoot != "" {
		cache = filepath.Join(result.ProjectRoot, ".ms-cache")
	}

	switch command {
	case "lint":
		findings := []tooling.LintFinding{}
		for _, module := range result.Program.Modules {
			findings = append(findings, tooling.Lint(module.File, module.Source)...)
		}
		findings = append(findings, tooling.LintProgram(result.Program)...)
		if structured {
			data, _ := json.Marshal(struct {
				Format      int                   `json:"format"`
				Diagnostics []tooling.LintFinding `json:"diagnostics"`
			}{1, findings})
			fmt.Println(string(data))
		} else {
			for _, f := range findings {
				if result.SourceRoot != "" && !filepath.IsAbs(f.Position.File) {
					f.Position.File = filepath.Join(result.SourceRoot, f.Position.File)
				}
				fmt.Fprintf(os.Stderr, "%s: %s: %s\n", f.Position, f.Code, f.Message)
			}
		}
		if len(findings) > 0 {
			return 1
		}
		return 0
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
		return writeOutput(output, []byte(source))
	case "check":
		fmt.Println("Checked", filename)
		return 0
	case "emit":
		source, err := compiler.Standalone(result.Source)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 1
		}
		return writeOutput(output, []byte(source))
	case "build":
		if output == "" {
			output = "program"
			if runtime.GOOS == "windows" {
				output += ".exe"
			}
		}
		absolute, err := filepath.Abs(output)
		if err == nil {
			if cache == "" {
				cache = filepath.Join(filepath.Dir(absolute), ".ms-cache")
			}
			_, err = compiler.BuildCheckedWithType(result, absolute, cache, kind)
		}
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 1
		}
		fmt.Println("Built", output)
		return 0
	default:
		if cache == "" {
			var err error
			cache, err = compiler.DefaultBuildCacheDir()
			if err != nil {
				fmt.Fprintln(os.Stderr, err)
				return 1
			}
		}
		directory, err := os.MkdirTemp("", "manuscript-run-")
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 1
		}
		defer os.RemoveAll(directory)
		executable := filepath.Join(directory, "program")
		if command == "profile" {
			executable = filepath.Join(output, "program")
		}
		if runtime.GOOS == "windows" {
			executable += ".exe"
		}

		if _, err := compiler.BuildCheckedWithType(result, executable, cache, kind); err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 1
		}
		if command == "profile" {
			manifest, _ := json.MarshalIndent(map[string]any{"format": 1, "source_root": result.SourceRoot, "executable": filepath.Base(executable), "inspection": "inspection.json", "cpu_profile": "cpu.pprof", "heap_profile": "heap.pprof", "trace": "trace.out"}, "", "  ")
			if err := os.WriteFile(filepath.Join(output, "manifest.json"), manifest, 0600); err != nil {
				fmt.Fprintln(os.Stderr, err)
				return 1
			}
			inspection, err := json.MarshalIndent(tooling.Inspect(result.Program), "", "  ")
			if err == nil {
				err = os.WriteFile(filepath.Join(output, "inspection.json"), inspection, 0600)
			}
			if err != nil {
				fmt.Fprintln(os.Stderr, err)
				return 1
			}
		}
		child := exec.Command(executable, arguments...)
		if command == "debug" {
			dlv, e := exec.LookPath("dlv")
			if e != nil {
				fmt.Fprintln(os.Stderr, "debug requires Delve (dlv) on PATH")
				return 1
			}
			dlvArgs := append([]string{"exec", executable, "--"}, arguments...)
			child = exec.Command(dlv, dlvArgs...)
		}
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

// Diagnostics retain the caller's logical source identity internally and use
// absolute paths only when rendered to a terminal.
func reportDiagnostics(result compiler.Result) int {
	for _, issue := range result.Diagnostics {
		if result.SourceRoot != "" && !filepath.IsAbs(issue.Position.File) {
			issue.Position.File = filepath.Join(result.SourceRoot, issue.Position.File)
		}
		fmt.Fprintln(os.Stderr, issue)
	}
	return 1
}

func writeOutput(filename string, data []byte) int {
	var err error
	if filename == "" {
		_, err = os.Stdout.Write(data)
	} else {
		err = os.WriteFile(filename, data, 0644)
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	return 0
}
