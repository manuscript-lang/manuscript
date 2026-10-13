// Package cli implements Manuscript command orchestration.
package cli

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	support "github.com/manuscript-lang/manuscript"
	"github.com/manuscript-lang/manuscript/internal/debugger"
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"github.com/manuscript-lang/manuscript/pkg/stdlib"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
	"github.com/manuscript-lang/manuscript/pkg/tooling"
	"github.com/manuscript-lang/manuscript/pkg/tooling/lsp"
	"io/fs"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"runtime"
	"strings"
	"syscall"
	"time"
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
		unknownCommand(args[0])
		return 2
	}
	if requestsHelp(args[1:]) {
		fmt.Print(usage)
		return 0
	}
	if args[0] == "pprof" || args[0] == "trace" {
		command, err := compiler.ProfileCommand(args[0], args[1:]...)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 1
		}
		command.Stdin, command.Stdout, command.Stderr = os.Stdin, os.Stdout, os.Stderr
		if err := runWithSignals(command); err != nil {
			if exit, ok := err.(*exec.ExitError); ok {
				return exit.ExitCode()
			}
			fmt.Fprintln(os.Stderr, err)
			return 1
		}
		return 0
	}
	if args[0] == "help" {
		return runHelp(args[1:])
	}
	if args[0] == "doc" {
		return runDoc(args[1:])
	}
	if args[0] == "init" {
		return runInit(args[1:])
	}
	if args[0] == "fmt" {
		return runFormat(args[1:])
	}
	if args[0] == "dap" {
		if len(args) != 1 {
			fmt.Fprintln(os.Stderr, "ms dap takes no arguments; it serves one session on stdin/stdout")
			return 2
		}
		ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
		defer cancel()
		transport := &dapStdio{os.Stdin, os.Stdout}
		// Keep any locally directed target/Delve output out of the protocol stream.
		// The editor asks for outputMode=remote to receive DAP output events.
		stdout := os.Stdout
		os.Stdout = os.Stderr
		defer func() { os.Stdout = stdout }()
		debugger.DAP(ctx, transport)
		return 0
	}
	if args[0] == "lsp" {
		if err := lsp.Serve(os.Stdin, os.Stdout); err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 1
		}
		return 0
	}
	if args[0] == "stdlib" {
		if len(args) != 2 {
			fmt.Fprintln(os.Stderr, "ms stdlib: pass exactly one directory to write the standard declarations into, e.g. ms stdlib ./declarations")
			fmt.Fprintln(os.Stderr)
			fmt.Fprint(os.Stderr, usage)
			return 2
		}
		if err := stdlib.Materialize(args[1]); err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 1
		}
		return 0
	}
	if len(args) < 2 {
		fmt.Fprintf(os.Stderr, "ms %s: missing the file argument; pass a .ms file or a project ms.toml, e.g. ms %s ms.toml\n\n", args[0], args[0])
		fmt.Fprint(os.Stderr, usage)
		return 2
	}
	command, filename := args[0], args[1]
	if strings.HasPrefix(filename, "-") && filename != "--" {
		fmt.Fprintf(os.Stderr, "unknown option %s for ms %s; run 'ms help %s' for its options (put the file first, then options)\n", filename, command, command)
		return 2
	}
	if info, err := os.Stat(filename); err == nil && info.IsDir() {
		manifest := filepath.Join(filename, "ms.toml")
		if _, err := os.Stat(manifest); err != nil {
			fmt.Fprintf(os.Stderr, "ms %s: %s is a directory without an ms.toml; pass a .ms file or a project ms.toml, e.g. ms %s ms.toml\n", command, filename, command)
			return 2
		}
		filename = manifest
	}
	output := ""
	cpuProfile, heapProfile, tracePath := "", "", ""
	profileTrace := false
	formatCheck, structured, debug, watch := false, false, false, false
	buildTypeName := ""
	buildTypeSet := false
	testTimeout, testFilter := "", ""
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
				fmt.Fprintln(os.Stderr, "--build-type requires a build type; use Debug, Release, RelWithDebInfo, or MinSizeRel")
				return 2
			}
			if buildTypeSet {
				fmt.Fprintln(os.Stderr, "--build-type may only be specified once; remove the duplicate flag")
				return 2
			}
			buildTypeName, buildTypeSet = args[i], true
		case "--timeout", "--filter":
			flag := args[i]
			i++
			if i == len(args) || flag == "--filter" && args[i] == "" {
				fmt.Fprintf(os.Stderr, "%s requires a value, e.g. %s\n", flag, map[string]string{"--timeout": "--timeout 30s", "--filter": "--filter \"test name\""}[flag])
				return 2
			}
			if flag == "--timeout" {
				if d, err := time.ParseDuration(args[i]); err != nil || d < 0 {
					fmt.Fprintf(os.Stderr, "invalid --timeout %q; use a duration such as 30s or 2m, or 0 to disable\n", args[i])
					return 2
				}
				testTimeout = args[i]
			} else {
				testFilter = args[i]
			}
		case "--check":
			formatCheck = true
		case "--json":
			structured = true
		case "-o", "--output", "--cpu-profile", "--heap-profile", "--trace":
			flag := args[i]
			if flag == "--trace" && command == "profile" {
				// Execution tracing is opt-in for profiles: it records an event per call.
				profileTrace = true
				continue
			}
			i++
			if i == len(args) {
				message := flag + " requires a path argument, e.g. " + flag + " out.pprof"
				if flag == "-o" || flag == "--output" {
					message = flag + " requires a path argument, e.g. " + flag + " out.go"
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
			if !strings.HasPrefix(args[i], "-") {
				fmt.Fprintf(os.Stderr, "unexpected extra argument %s (ms %s takes one file; arguments for the program go after --)\n", args[i], command)
				return 2
			}
			fmt.Fprintf(os.Stderr, "unknown option %s for ms %s; run 'ms help %s' for its options (arguments for the program go after --)\n", args[i], command, command)
			return 2
		}
	}
	options := compiler.Options{}
	switch command {
	case "check", "lint", "inspect", "diagram", "lock":
		options.AnalyzeOnly = true
		options.ProjectSources = command == "check"
		options.Entry = command != "lint" && filepath.Base(filename) == "ms.toml"
	case "emit": // Only source emission needs lowering without an entry launcher.
	case "build", "run", "debug", "profile":
		options.Entry = true
	case "test":
		options.Tests = true
	default:
		unknownCommand(command)
		return 2
	}
	if (testTimeout != "" || testFilter != "") && command != "test" {
		fmt.Fprintf(os.Stderr, "--timeout and --filter are valid only for ms test, not ms %s; run 'ms help %s' for the options this command accepts\n", command, command)
		return 2
	}
	if command == "test" {
		var testArgs []string
		if testTimeout != "" {
			testArgs = append(testArgs, "--timeout="+testTimeout)
		}
		if testFilter != "" {
			testArgs = append(testArgs, "--filter="+testFilter)
		}
		arguments = append(testArgs, arguments...)
	}
	if watch && command != "run" && command != "test" {
		fmt.Fprintf(os.Stderr, "--watch requires run or test, not %s; use ms run <file> --watch or ms test <file> --watch\n", command)
		return 2
	}
	if formatCheck && command != "fmt" || structured && command != "check" && command != "lint" || debug && command != "build" && command != "run" && command != "test" {
		fmt.Fprintf(os.Stderr, "%s; run 'ms help %s' for the options this command accepts\n", invalidFlag(command, formatCheck, structured, debug), command)
		return 2
	}
	kind, err := compiler.ParseBuildType(buildTypeName)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 2
	}
	if buildTypeSet && command != "build" && command != "run" && command != "test" && command != "debug" && command != "profile" {
		fmt.Fprintf(os.Stderr, "--build-type requires build, run, test, debug, or profile, not %s; remove the flag\n", command)
		return 2
	}
	if debug || command == "debug" {
		if buildTypeSet && kind != compiler.Debug {
			fmt.Fprintln(os.Stderr, "debug requires build type Debug; remove --build-type or pass --build-type Debug")
			return 2
		}
		kind = compiler.Debug
	} else if command == "profile" && !buildTypeSet {
		kind = compiler.RelWithDebInfo
	}
	if (cpuProfile != "" || heapProfile != "" || tracePath != "") && command != "run" {
		fmt.Fprintf(os.Stderr, "profiling flags (--cpu-profile, --heap-profile, --trace) require run, not %s; use ms run <file> with them, or ms profile <file> to capture all three\n", command)
		return 2
	}
	if watch && (cpuProfile != "" || heapProfile != "" || tracePath != "") {
		fmt.Fprintln(os.Stderr, "--watch cannot be combined with profiling flags; run the profile once without --watch")
		return 2
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
		if profileTrace {
			tracePath = filepath.Join(output, "trace.out")
		}
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
	if structured && command == "check" || structured && command == "lint" && !result.Success() {
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
			fmt.Fprintf(os.Stderr, "profile directory must be new: %v; choose a path that does not exist with -o <directory>, or delete the old one\n", err)
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
		// Bundled standard modules are not the user's to fix.
		for _, module := range result.Program.Modules {
			if !strings.HasPrefix(module.File, "@std/") {
				findings = append(findings, tooling.Lint(module.File, module.Source)...)
			}
		}
		for _, finding := range tooling.LintProgram(result.Program) {
			if !strings.HasPrefix(finding.Position.File, "@std/") {
				findings = append(findings, finding)
			}
		}
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
			fmt.Fprintln(os.Stderr, "lock requires a project ms.toml, not a single .ms file; run ms lock path/to/ms.toml (a manifest declares [project] name, source, and entry)")
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
		if result.ProjectRoot != "" {
			count := 0
			for _, module := range result.Program.Modules {
				if !strings.HasPrefix(module.File, "@std/") {
					count++
				}
			}
			fmt.Printf("Checked %s (%d %s)\n", filename, count, plural(count, "module", "modules"))
		} else {
			fmt.Println("Checked", filename)
		}
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
			if info, statErr := os.Stat(absolute); statErr == nil && info.IsDir() {
				fmt.Fprintf(os.Stderr, "-o %s is a directory; pass a file path (e.g. -o %s)\n", output, filepath.Join(output, "program"))
				return 2
			}
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
			bundle := map[string]any{"format": 1, "source_root": result.SourceRoot, "executable": filepath.Base(executable), "inspection": "inspection.json", "cpu_profile": "cpu.pprof", "heap_profile": "heap.pprof"}
			if profileTrace {
				bundle["trace"] = "trace.out"
			}
			manifest, _ := json.MarshalIndent(bundle, "", "  ")
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
		if command == "debug" {
			ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGTERM)
			defer cancel()
			status, err := debugger.Terminal(ctx, executable, arguments)
			if err != nil {
				fmt.Fprintln(os.Stderr, err)
			}
			return status
		}
		child := exec.Command(executable, arguments...)
		child.Dir = testWorkingDirectory(command, filename, result)
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
	fmt.Fprintf(os.Stderr, "%d %s; fix them and re-run (ms check <file> --json gives the same diagnostics as structured data)\n", len(result.Diagnostics), plural(len(result.Diagnostics), "error", "errors"))
	return 1
}

func plural(n int, one, many string) string {
	if n == 1 {
		return one
	}
	return many
}

var commandNames = []string{"check", "lint", "build", "emit", "run", "test", "fmt", "inspect", "diagram", "profile", "debug", "lock", "init", "doc", "stdlib", "lsp", "help"}

// unknownCommand names the nearest command and lists the rest.
func unknownCommand(name string) {
	fmt.Fprintln(os.Stderr, "unknown command:", name)
	best, bestDistance := "", 3
	for _, candidate := range commandNames {
		if d := distance(name, candidate); d < bestDistance {
			best, bestDistance = candidate, d
		}
	}
	if best != "" {
		fmt.Fprintf(os.Stderr, "Did you mean 'ms %s'?\n", best)
	}
	fmt.Fprintf(os.Stderr, "Commands: %s. Run 'ms --help' for details.\n", strings.Join(commandNames, ", "))
}

func distance(a, b string) int {
	previous := make([]int, len(b)+1)
	for j := range previous {
		previous[j] = j
	}
	for i := 1; i <= len(a); i++ {
		current := make([]int, len(b)+1)
		current[0] = i
		for j := 1; j <= len(b); j++ {
			cost := 1
			if a[i-1] == b[j-1] {
				cost = 0
			}
			current[j] = min(previous[j]+1, current[j-1]+1, previous[j-1]+cost)
		}
		previous = current
	}
	return previous[len(b)]
}

// invalidFlag names the flag that this command does not accept.
func invalidFlag(command string, formatCheck, structured, debug bool) string {
	switch {
	case formatCheck && command != "fmt":
		return "--check is valid only for ms fmt, not ms " + command
	case structured:
		return "--json is valid only for ms check and ms lint, not ms " + command
	case debug:
		return "--debug is valid only for ms build, run, and test, not ms " + command
	}
	return "an option is not valid for ms " + command
}

// fileError turns a failed file read into a cause and a fix.
func fileError(err error) string {
	var pathError *fs.PathError
	if errors.As(err, &pathError) && errors.Is(err, fs.ErrNotExist) {
		return "file not found: " + pathError.Path + "; check the path and run from the directory that contains it"
	}
	return err.Error()
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

// dapStdio owns both protocol handles; closing interrupts blocked reads/writes.
type dapStdio struct {
	*os.File
	output *os.File
}

func (s *dapStdio) Write(p []byte) (int, error) { return s.output.Write(p) }

func (s *dapStdio) Close() error { _ = s.output.Close(); return s.File.Close() }

// Tests run in the project directory (the one holding ms.toml), or beside the
// test file for a single-file run, so fixtures such as "golden/x.md" resolve the
// same way wherever ms is invoked. Other commands keep the caller's directory.
func testWorkingDirectory(command, filename string, result compiler.Result) string {
	if command != "test" {
		return ""
	}
	directory := result.ProjectRoot
	if directory == "" {
		directory = filepath.Dir(filename)
	}
	if absolute, err := filepath.Abs(directory); err == nil {
		return absolute
	}
	return ""
}
