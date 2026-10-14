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
		return runAnalysis(inv.command, inv.targets, inv.structured)
	case "build", "profile":
		return runNativeCommand(inv.command, inv.filename, inv.output, p.options, p.kind, inv.arguments, inv.profileTrace, inv.structured)
	}
	if inv.isOneOf("run", "test", "debug") {
		// Native commands need the build pin; query the toolchain and hash
		// embedded inputs while the source is parsed and checked.
		go build.CurrentPin()
	}
	if inv.watch {
		return watchProgram(inv.command, inv.filename, p.options, p.kind, inv.arguments)
	}
	result := compiler.CompileFileForBuild(inv.filename, p.options, p.kind)
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
	case "lock":
		return lockProject(inv.filename, result)
	case "inspect", "diagram":
		return inspectProgram(inv.command, inv.output, result)
	case "emit":
		return emitSource(inv.output, result)
	}
	return runNativeProgram(inv, p.kind, result)
}

func lockProject(filename string, result compiler.Result) int {
	if result.ProjectRoot == "" {
		fmt.Fprintln(os.Stderr, "lock requires a project ms.toml, not a single .ms file; run ms lock path/to/ms.toml (a manifest declares [project] name and source, plus entry for an executable)")
		return 2
	}
	if err := build.WritePin(result.ProjectRoot); err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	fmt.Println("Pinned", filename)
	return 0
}

func inspectProgram(command, output string, result compiler.Result) int {
	inspection := tooling.Inspect(result.Program)
	if command == "diagram" {
		return writeOutput(output, []byte(tooling.Diagram(inspection)))
	}
	data, err := json.MarshalIndent(inspection, "", "  ")
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
		ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGTERM)
		defer cancel()
		status, err := debugger.Terminal(ctx, executable, inv.arguments)
		if err != nil {
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
