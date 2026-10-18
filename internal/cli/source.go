package cli

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"runtime"
	"syscall"

	"github.com/manuscript-lang/manuscript/internal/debugger"
	"github.com/manuscript-lang/manuscript/pkg/build"
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"github.com/manuscript-lang/manuscript/pkg/tooling"
)

// runSourceCommand runs a command that takes a source file or project: parse
// and validate its options, check the source once, then deliver the result.
func runSourceCommand(args []string, usage string) int {
	if len(args) < 2 {
		fmt.Fprintf(os.Stderr, "ms %s: missing the file argument; pass a .ms file or a project ms.toml, e.g. ms %s ms.toml\n\n", args[0], args[0])
		fmt.Fprint(os.Stderr, usage)
		return 2
	}
	inv, status, ok := parseInvocation(args)
	if !ok {
		return status
	}
	p, status, ok := inv.validate()
	if !ok {
		return status
	}
	switch inv.command {
	case "check", "lint":
		if inv.watch {
			return watchAnalysis(inv.command, inv.targets)
		}
		return runAnalysis(inv.command, inv.targets, inv.structured)
	case "build", "profile":
		return runNativeCommand(inv.command, inv.filename, inv.output, p.options, p.kind, inv.arguments, inv.profileTrace, inv.structured)
	}
	if inv.isOneOf("run", "test", "debug") {
		// Native commands need the build identity; query the toolchain and hash
		// embedded inputs while the source is parsed and checked.
		go build.CurrentPin()
	}
	if inv.watch {
		return watchProgram(inv.command, inv.filename, p.options, p.kind, inv.arguments)
	}
	p.options.BuildType = p.kind
	result := compiler.CompileFile(inv.filename, p.options)
	if !result.Success() {
		if inv.structured && inv.command == "test" {
			document := newTestResult(result)
			document.Reason = "compile_error"
			return emitJSON(document, 1)
		}
		if inv.structured {
			return emitJSON(structuredDiagnostics(result), 1)
		}
		return reportDiagnostics(result)
	}
	if inv.output != "" && inv.isOneOf("emit", "inspect", "diagram") {
		if protected := protectedOutput(inv.output, inv.filename, result.ProjectRoot); protected != "" {
			fmt.Fprintf(os.Stderr, "-o %s would overwrite %s; choose a different output path\n", inv.output, protected)
			return 2
		}
	}
	switch inv.command {
	case "inspect", "diagram":
		return inspectProgram(inv, result)
	case "emit":
		return emitSource(inv.output, result)
	}
	return runNativeProgram(inv, p.kind, result)
}

func inspectProgram(inv *invocation, result compiler.Result) int {
	command, output, format := inv.command, inv.output, inv.format
	inspection := tooling.Inspect(result.Program)
	if command == "diagram" && (inv.view != "" || inv.entity != "") {
		return writeView(inv, result)
	}
	if command == "diagram" {
		if format == "mermaid" {
			return writeOutput(output, []byte(tooling.Diagram(inspection)))
		}
		return writeOutput(output, []byte(tooling.DiagramASCII(inspection)))
	}
	data, err := json.MarshalIndent(inspectionWithGoLocals(result), "", "  ")
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	return writeOutput(output, append(data, '\n'))
}

func emitSource(output string, result compiler.Result) int {
	source, err := build.Standalone(result.Source)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	return writeOutput(output, []byte(source))
}

// runNativeProgram builds the checked program and runs, tests, or debugs it.
func runNativeProgram(inv *invocation, kind compiler.BuildType, result compiler.Result) int {
	command, filename := inv.command, inv.filename
	jsonTest := inv.structured && command == "test"
	// failure reports a build-stage error in the format the command was asked for.
	failure := func(phase string, err error) int {
		if jsonTest {
			return testJSONError(filename, result, phase, err)
		}
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	directory, err := os.MkdirTemp("", "manuscript-run-")
	if err != nil {
		return failure("execution", err)
	}
	defer os.RemoveAll(directory)
	executable := filepath.Join(directory, "program")
	if runtime.GOOS == "windows" {
		executable += ".exe"
	}
	if _, err := build.BuildCheckedWithType(result, executable, kind); err != nil {
		return failure("build", err)
	}
	if command == "debug" {
		signals := []os.Signal{syscall.SIGTERM}
		if inv.debugScript != "" || len(inv.debugBreaks) > 0 {
			signals = append(signals, os.Interrupt)
		}
		ctx, cancel := signal.NotifyContext(context.Background(), signals...)
		defer cancel()
		if inv.debugScript != "" || len(inv.debugBreaks) > 0 {
			return runDebugScript(ctx, inv, result, executable)
		}
		status, err := debugger.Terminal(ctx, executable, inv.arguments)
		if err != nil && ctx.Err() == nil {
			fmt.Fprintln(os.Stderr, err)
		}
		return status
	}
	child := exec.Command(executable, inv.arguments...)
	child.Dir = testWorkingDirectory(command, filename, result)
	child.Stdin = os.Stdin
	if jsonTest {
		return runTestJSON(child, result)
	}
	child.Stdout = os.Stdout
	child.Stderr = os.Stderr
	return waitForChild(child)
}

// runDebugScript drives the Debug build from a command file or one-shot breakpoints.
func runDebugScript(ctx context.Context, inv *invocation, result compiler.Result, executable string) int {
	opts := debugger.Options{Breaks: inv.debugBreaks, JSON: inv.structured, Out: os.Stdout, Args: inv.arguments, Names: debugNames(result)}
	if inv.debugScript != "" {
		opts.Script = os.Stdin
		if inv.debugScript != "-" {
			file, err := os.Open(inv.debugScript)
			if err != nil {
				fmt.Fprintln(os.Stderr, err)
				return 1
			}
			defer file.Close()
			opts.Script = file
		}
	}
	status, err := debugger.Script(ctx, executable, opts)
	if err != nil && ctx.Err() == nil {
		_ = debugger.ReportError(ctx, os.Stderr, err)
	}
	return status
}

// writeView prints one scoped diagram view of the checked program.
func writeView(inv *invocation, result compiler.Result) int {
	view := inv.view
	if view == "" {
		view = "calls"
	}
	facts := tooling.CollectFacts(result.Program)
	tree, err := tooling.BuildView(facts, view, inv.entity, inv.depth)
	if err != nil {
		fmt.Fprintf(os.Stderr, "ms diagram: %v\n", err)
		return 2
	}
	if inv.diff != "" {
		entry := filepath.Base(inv.filename) == "ms.toml"
		input, base, status := diffInputs(inv.filename, inv.diff, result, entry)
		if status != 0 {
			return status
		}
		tooling.MarkChanges(tree, tooling.CompareFacts(base, facts, input), input.Touched)
	}
	if inv.format == "mermaid" {
		return writeOutput(inv.output, []byte(tree.Mermaid()))
	}
	return writeOutput(inv.output, []byte(tree.ASCII()))
}
