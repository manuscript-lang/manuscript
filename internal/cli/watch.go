package cli

import (
	"fmt"
	"github.com/manuscript-lang/manuscript/pkg/build"
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
	"time"
)

// Source files are polled; a handful of stat calls per interval costs nothing
// measurable. Editors often save in several steps, so wait for them to settle.
const watchInterval = 10 * time.Millisecond
const watchSettle = 10 * time.Millisecond

// A replaced program gets this long to finish cancellation and cleanup.
const watchGrace = 5 * time.Second

// watchProgram rebuilds and restarts an application or test executable after
// each saved change to its sources or manifest. The previous program keeps
// running until a replacement builds, so a failed edit only reports
// diagnostics. One process keeps standard declarations, the toolchain query,
// and build pins warm across rebuilds.
func watchProgram(command, filename string, options compiler.Options, kind compiler.BuildType, arguments []string) int {
	directory, err := os.MkdirTemp("", "manuscript-watch-")
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	defer os.RemoveAll(directory)
	stops := make(chan os.Signal, 2)
	signal.Notify(stops, os.Interrupt, syscall.SIGTERM)
	defer signal.Stop(stops)

	var child *exec.Cmd
	exited := make(chan error, 1)
	watched := map[string]fileState{}
	generation := 0
	rebuild := func(started time.Time, reason string) {
		result := compiler.CompileFileForBuild(filename, options, kind)
		for _, path := range watchedFiles(filename, result) {
			if _, ok := watched[path]; !ok {
				watched[path] = statFile(path)
			}
		}
		if !result.Success() {
			reportDiagnostics(result)
			fmt.Fprintln(os.Stderr, "ms: waiting for changes")
			return
		}
		generation++
		executable := filepath.Join(directory, fmt.Sprintf("program-%d", generation))
		if _, err := build.BuildCheckedWithType(result, executable, kind); err != nil {
			fmt.Fprintln(os.Stderr, err)
			fmt.Fprintln(os.Stderr, "ms: waiting for changes")
			return
		}
		if child != nil {
			stopChild(child, exited)
			os.Remove(child.Path)
			child = nil
		}
		next := exec.Command(executable, arguments...)
		next.Dir = testWorkingDirectory(command, filename, result)
		next.Stdin, next.Stdout, next.Stderr = os.Stdin, os.Stdout, os.Stderr
		if err := next.Start(); err != nil {
			fmt.Fprintln(os.Stderr, err)
			return
		}
		fmt.Fprintf(os.Stderr, "ms: %s %s in %d ms\n", reason, command, time.Since(started).Milliseconds())
		child = next
		go func() { exited <- next.Wait() }()
	}
	rebuild(time.Now(), "started")

	poll := time.NewTicker(watchInterval)
	defer poll.Stop()
	var settle <-chan time.Time
	var changed time.Time
	for {
		select {
		case stop := <-stops:
			if child != nil {
				_ = child.Process.Signal(stop)
				waitChild(child, exited)
			}
			return 130
		case err := <-exited:
			status := 0
			if exit, ok := err.(*exec.ExitError); ok {
				status = exit.ExitCode()
			} else if err != nil {
				fmt.Fprintln(os.Stderr, err)
			}
			child = nil
			fmt.Fprintf(os.Stderr, "ms: exited with status %d; waiting for changes\n", status)
		case <-poll.C:
			for path, previous := range watched {
				if current := statFile(path); current != previous {
					watched[path] = current
					if settle == nil {
						changed = time.Now()
					}
					settle = time.After(watchSettle)
				}
			}
		case <-settle:
			settle = nil
			rebuild(changed, "restarted")
		}
	}
}

// watchedFiles lists the manifest and every local module the program loaded.
func watchedFiles(filename string, result compiler.Result) []string {
	var files []string
	if absolute, err := filepath.Abs(filename); err == nil {
		files = append(files, absolute)
	}
	if result.ProjectRoot != "" {
		files = append(files, filepath.Join(result.ProjectRoot, "ms.toml"), filepath.Join(result.ProjectRoot, "ms.lock"))
	}
	if result.Program == nil {
		return files
	}
	for _, module := range result.Program.Modules {
		if strings.HasPrefix(module.File, "@std/") {
			continue
		}
		path := filepath.FromSlash(module.File)
		if !filepath.IsAbs(path) && result.SourceRoot != "" {
			path = filepath.Join(result.SourceRoot, path)
		}
		if absolute, err := filepath.Abs(path); err == nil {
			files = append(files, absolute)
		}
	}
	return files
}

// stopChild interrupts a replaced program and waits for its cleanup, killing
// it after the grace period.
func stopChild(child *exec.Cmd, exited chan error) {
	if err := child.Process.Signal(os.Interrupt); err != nil {
		_ = child.Process.Kill()
	}
	waitChild(child, exited)
}

func waitChild(child *exec.Cmd, exited chan error) {
	select {
	case <-exited:
	case <-time.After(watchGrace):
		_ = child.Process.Kill()
		<-exited
	}
}

type fileState struct {
	exists  bool
	size    int64
	modTime time.Time
}

func statFile(path string) fileState {
	info, err := os.Stat(path)
	if err != nil {
		return fileState{}
	}
	return fileState{exists: true, size: info.Size(), modTime: info.ModTime()}
}
