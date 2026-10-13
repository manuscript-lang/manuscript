// Package cli implements Manuscript command orchestration.
package cli

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"github.com/manuscript-lang/manuscript/internal/debugger"
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"github.com/manuscript-lang/manuscript/pkg/stdlib"
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
	if args[0] == "--version" || args[0] == "version" {
		return runVersion(args[0], args[1:])
	}
	usage, known := commandHelp(args[0])
	if !known {
		unknownCommand(args[0])
		return 2
	}
	if requestsHelp(args[0], args[1:]) {
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
	analysis := command == "check" || command == "lint"
	first, positional := 1, false
	if analysis && filename == "--" {
		if len(args) == 2 {
			fmt.Fprintf(os.Stderr, "ms %s: missing a target; pass .ms files, directories, or ms.toml\n", command)
			return 2
		}
		first, filename, positional = 2, args[2], true
	}
	if strings.HasPrefix(filename, "-") && filename != "--" && !positional {
		fmt.Fprintf(os.Stderr, "unknown option %s for ms %s; run 'ms help %s' for its options (put the file first, then options)\n", filename, command, command)
		return 2
	}
	if !analysis {
		var err error
		filename, err = resolveInput(command, filename)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 2
		}
	}
	targets := []string{filename}
	output := ""
	cpuProfile, heapProfile, tracePath := "", "", ""
	profileTrace := false
	formatCheck, structured, debug, watch := false, false, false, false
	buildTypeName := ""
	buildTypeSet := false
	testTimeout, testFilter := "", ""
	var arguments []string
	for i := first + 1; i < len(args); i++ {
		if positional {
			targets = append(targets, args[i])
			continue
		}
		flag, value, inline := splitCommandValueOption(command, args[i])
		switch flag {
		case "--":
			if analysis {
				targets = append(targets, args[i+1:]...)
			} else {
				arguments = args[i+1:]
			}
			i = len(args)
		case "--debug":
			debug = true
		case "--watch":
			watch = true
		case "--build-type":
			value, ok := requiredValue(args, &i, value, inline)
			if !ok {
				fmt.Fprintln(os.Stderr, "--build-type requires a build type; use Debug, Release, RelWithDebInfo, or MinSizeRel")
				return 2
			}
			if buildTypeSet {
				fmt.Fprintln(os.Stderr, "--build-type may only be specified once; remove the duplicate flag")
				return 2
			}
			buildTypeName, buildTypeSet = value, true
		case "--timeout", "--filter":
			value, ok := requiredValue(args, &i, value, inline)
			if !ok {
				fmt.Fprintf(os.Stderr, "%s requires a value, e.g. %s\n", flag, map[string]string{"--timeout": "--timeout 30s", "--filter": "--filter \"test name\""}[flag])
				return 2
			}
			if flag == "--timeout" {
				if d, err := time.ParseDuration(value); err != nil || d < 0 {
					fmt.Fprintf(os.Stderr, "invalid --timeout %q; use a duration such as 30s or 2m, or 0 to disable\n", value)
					return 2
				}
				testTimeout = value
			} else {
				testFilter = value
			}
		case "--check":
			formatCheck = true
		case "--json":
			structured = true
		case "--trace":
			if command == "profile" {
				profileTrace = true
				continue
			}
			fallthrough
		case "-o", "--output", "--out-dir", "--cpu-profile", "--heap-profile":
			value, ok := requiredValue(args, &i, value, inline)
			if !ok {
				message := flag + " requires a path argument, e.g. " + flag + " out.pprof"
				if flag == "-o" || flag == "--output" || flag == "--out-dir" {
					message = flag + " requires a path argument, e.g. " + flag + " out.go"
				}
				fmt.Fprintln(os.Stderr, message)
				return 2
			}
			switch flag {
			case "-o", "--output", "--out-dir":
				if flag == "--out-dir" && command != "profile" {
					fmt.Fprintf(os.Stderr, "--out-dir is valid only for ms profile, not ms %s; use -o for commands that write a file\n", command)
					return 2
				}
				output = value
			case "--cpu-profile":
				cpuProfile = value
			case "--heap-profile":
				heapProfile = value
			case "--trace":
				tracePath = value
			}
		default:
			if !strings.HasPrefix(args[i], "-") {
				if analysis {
					targets = append(targets, args[i])
					continue
				}
				fmt.Fprintf(os.Stderr, "unexpected extra argument %s (ms %s takes one file; arguments for the program go after --)\n", args[i], command)
				return 2
			}
			fmt.Fprintf(os.Stderr, "unknown option %s for ms %s; run 'ms help %s' for its options (arguments for the program go after --)\n", args[i], command, command)
			return 2
		}
	}
	options := compiler.Options{}
	switch command {
	case "check", "lint": // Independent source requests run after flag validation.
	case "inspect", "diagram", "lock":
		options.AnalyzeOnly = true
		options.Entry = filepath.Base(filename) == "ms.toml"
	case "emit": // Only source emission needs lowering without an entry launcher.
	case "build", "run", "debug", "profile":
		options.Entry = true
	case "test":
		options.Tests = true
	default:
		unknownCommand(command)
		return 2
	}
	if output != "" && command != "build" && command != "emit" && command != "inspect" && command != "diagram" && command != "profile" {
		fmt.Fprintf(os.Stderr, "-o and --output are valid only for ms build, emit, inspect, diagram, doc, or profile, not ms %s; run 'ms help %s' for its options\n", command, command)
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
	if watch && structured {
		fmt.Fprintln(os.Stderr, "--json cannot be combined with --watch; remove --watch for one versioned test result")
		return 2
	}
	if watch && command != "run" && command != "test" {
		fmt.Fprintf(os.Stderr, "--watch requires run or test, not %s; use ms run <file> --watch or ms test <file> --watch\n", command)
		return 2
	}
	if formatCheck && command != "fmt" || structured && command != "check" && command != "lint" && command != "test" && command != "build" && command != "profile" || debug && command != "build" && command != "run" && command != "test" {
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
		fmt.Fprintf(os.Stderr, "profiling paths (--cpu-profile, --heap-profile, --trace) require run, not %s; use ms run <file> with them, or ms profile <file> [--trace] for a bundle\n", command)
		return 2
	}
	if watch && (cpuProfile != "" || heapProfile != "" || tracePath != "") {
		fmt.Fprintln(os.Stderr, "--watch cannot be combined with profiling flags; run the profile once without --watch")
		return 2
	}
	if analysis {
		return runAnalysis(command, targets, structured)
	}
	if command == "build" || command == "profile" {
		return runNativeCommand(command, filename, output, options, kind, arguments, profileTrace, structured)
	}

	options.CPUProfile, options.HeapProfile, options.Trace = cpuProfile, heapProfile, tracePath

	switch command {
	case "run", "test", "debug":
		// Native commands need the build pin; query the toolchain and hash
		// embedded inputs while the source is parsed and checked.
		go compiler.CurrentPin()
	}
	if watch {
		return watchProgram(command, filename, options, kind, "", arguments)
	}
	result := compiler.CompileFileForBuild(filename, options, kind)
	if !result.Success() {
		if structured && command == "test" {
			document := newTestResult(result)
			document.Reason = "compile_error"
			return emitJSON(document, 1)
		}
		return reportDiagnostics(result)
	}

	cache := ""
	if result.ProjectRoot != "" {
		cache = filepath.Join(result.ProjectRoot, ".ms-cache")
	}

	switch command {
	case "lock":
		if result.ProjectRoot == "" {
			fmt.Fprintln(os.Stderr, "lock requires a project ms.toml, not a single .ms file; run ms lock path/to/ms.toml (a manifest declares [project] name and source, plus entry for an executable)")
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
	case "emit":
		source, err := compiler.Standalone(result.Source)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 1
		}
		return writeOutput(output, []byte(source))
	default:
		if cache == "" {
			var err error
			cache, err = compiler.DefaultBuildCacheDir()
			if err != nil {
				if structured && command == "test" {
					return testJSONError(filename, result, "build", err)
				}
				fmt.Fprintln(os.Stderr, err)
				return 1
			}
		}
		directory, err := os.MkdirTemp("", "manuscript-run-")
		if err != nil {
			if structured && command == "test" {
				return testJSONError(filename, result, "execution", err)
			}
			fmt.Fprintln(os.Stderr, err)
			return 1
		}
		defer os.RemoveAll(directory)
		executable := filepath.Join(directory, "program")
		if runtime.GOOS == "windows" {
			executable += ".exe"
		}

		if _, err := compiler.BuildCheckedWithType(result, executable, cache, kind); err != nil {
			if structured && command == "test" {
				return testJSONError(filename, result, "build", err)
			}
			fmt.Fprintln(os.Stderr, err)
			return 1
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
		if command == "test" && structured {
			return runTestJSON(child, result)
		}
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
		return "--json is valid only for ms check, lint, test, build, and profile, not ms " + command
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
