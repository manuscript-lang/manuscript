// Package cli implements Manuscript command orchestration.
package cli

import (
	"errors"
	"fmt"
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"io/fs"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
)

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

// commandNames lists every dispatched command; a test keeps it equal to the help text.
var commandNames = []string{"check", "lint", "build", "emit", "run", "test", "fmt", "inspect", "diagram", "profile", "pprof", "trace", "debug", "dap", "lock", "init", "doc", "stdlib", "lsp", "help", "version"}

// jsonCommands accept --json; fmt and doc parse their own options but share the spelling.
var jsonCommands = []string{"check", "lint", "test", "build", "profile", "inspect", "diagram", "emit", "lock", "fmt", "doc", "debug"}

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
		return "--json is valid only for ms " + strings.Join(jsonCommands, ", ") + ", not ms " + command
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
