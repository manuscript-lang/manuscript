package cli

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"os/signal"
	"syscall"

	"github.com/manuscript-lang/manuscript/internal/debugger"
	"github.com/manuscript-lang/manuscript/pkg/build"
	"github.com/manuscript-lang/manuscript/pkg/stdlib"
	"github.com/manuscript-lang/manuscript/pkg/tooling/lsp"
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
	if run, ok := standaloneCommand(args[0]); ok {
		return run(args, usage)
	}
	return runSourceCommand(args, usage)
}

// standaloneCommand returns commands that take no source input and parse their own arguments.
func standaloneCommand(name string) (func(args []string, usage string) int, bool) {
	switch name {
	case "pprof", "trace":
		return runProfileTool, true
	case "help":
		return func(args []string, _ string) int { return runHelp(args[1:]) }, true
	case "doc":
		return func(args []string, _ string) int { return runDoc(args[1:]) }, true
	case "init":
		return func(args []string, _ string) int { return runInit(args[1:]) }, true
	case "fmt":
		return func(args []string, _ string) int { return runFormat(args[1:]) }, true
	case "dap":
		return runDAP, true
	case "lsp":
		return runLSP, true
	case "stdlib":
		return runStdlib, true
	}
	return nil, false
}

func runProfileTool(args []string, _ string) int {
	command, err := build.ProfileCommand(args[0], args[1:]...)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	command.Stdin, command.Stdout, command.Stderr = os.Stdin, os.Stdout, os.Stderr
	return waitForChild(command)
}

// waitForChild runs a child under signal forwarding and returns its exit status.
func waitForChild(child *exec.Cmd) int {
	if err := runWithSignals(child); err != nil {
		if exit, ok := err.(*exec.ExitError); ok {
			return exit.ExitCode()
		}
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	return 0
}

func runDAP(args []string, _ string) int {
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

func runLSP(_ []string, _ string) int {
	if err := lsp.Serve(os.Stdin, os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	return 0
}

func runStdlib(args []string, usage string) int {
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
