package cli

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"unicode/utf8"

	"github.com/manuscript-lang/manuscript/pkg/build"
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
	"github.com/manuscript-lang/manuscript/pkg/tooling"
)

type nativeResult struct {
	Format       int                 `json:"format"`
	Command      string              `json:"command"`
	BuildType    compiler.BuildType  `json:"build_type"`
	SourceRoot   string              `json:"source_root"`
	Output       string              `json:"output"`
	Completed    bool                `json:"completed"`
	ExitCode     int                 `json:"exit_code"`
	Reason       string              `json:"reason,omitempty"`
	Artifacts    []nativeArtifact    `json:"artifacts"`
	Stdout       string              `json:"stdout"`
	StdoutBase64 string              `json:"stdout_base64,omitempty"`
	Diagnostics  []commandDiagnostic `json:"diagnostics"`
}

type nativeArtifact struct {
	Kind  string `json:"kind"`
	Path  string `json:"path"`
	State string `json:"state"`
}

// Record the initial identity and stat so failures can distinguish preserved
// outputs from a partial publication. Successful builds verify their artifacts
// even when they reuse identical files from the native cache.
type artifactSnapshot struct {
	nativeArtifact
	before os.FileInfo
}

func nativeArtifactSnapshots(command, output string, trace bool) []artifactSnapshot {
	executable := output
	if command == "profile" {
		executable = filepath.Join(output, "program")
		if runtime.GOOS == "windows" {
			executable += ".exe"
		}
	}
	artifacts := []nativeArtifact{{Kind: "executable", Path: executable}, {Kind: "build_metadata", Path: executable + ".ms-build.json"}}
	if command == "profile" {
		artifacts = append(artifacts,
			nativeArtifact{Kind: "manifest", Path: filepath.Join(output, "manifest.json")},
			nativeArtifact{Kind: "inspection", Path: filepath.Join(output, "inspection.json")},
			nativeArtifact{Kind: "cpu_profile", Path: filepath.Join(output, "cpu.pprof")},
			nativeArtifact{Kind: "heap_profile", Path: filepath.Join(output, "heap.pprof")})
		if trace {
			artifacts = append(artifacts, nativeArtifact{Kind: "trace", Path: filepath.Join(output, "trace.out")})
		}
	}
	var snapshots []artifactSnapshot
	for _, artifact := range artifacts {
		info, _ := os.Stat(artifact.Path)
		snapshots = append(snapshots, artifactSnapshot{artifact, info})
	}
	return snapshots
}

func (document *nativeResult) inventory(snapshots []artifactSnapshot, verified map[string]bool) {
	document.Artifacts = []nativeArtifact{}
	for _, snapshot := range snapshots {
		artifact := snapshot.nativeArtifact
		artifact.State = "missing"
		info, err := os.Stat(artifact.Path)
		if err != nil && !os.IsNotExist(err) || err == nil && !info.Mode().IsRegular() {
			artifact.State = "unavailable"
		} else if err == nil {
			artifact.State = "preserved"
			if verified[artifact.Kind] {
				artifact.State = "verified"
			} else if snapshot.before == nil || !os.SameFile(snapshot.before, info) || snapshot.before.Size() != info.Size() || snapshot.before.ModTime() != info.ModTime() {
				artifact.State = "written"
			}
		}
		document.Artifacts = append(document.Artifacts, artifact)
	}
}

// Build/profile share one lifecycle; structured output changes only reporting
// and the optional stdout capture, not checking, caching, collectors or launch.
func runNativeCommand(command, filename, output string, options compiler.Options, kind compiler.BuildType, arguments []string, trace, structured bool) int {
	if output == "" {
		output = "profile"
		if command == "build" {
			output = "program"
			if runtime.GOOS == "windows" {
				output += ".exe"
			}
		}
	}
	displayOutput := output
	absolute, pathErr := filepath.Abs(output)
	if pathErr == nil {
		output = absolute
	}
	document := nativeResult{Format: 1, Command: command, BuildType: kind, Output: output, ExitCode: 1, Artifacts: []nativeArtifact{}, Diagnostics: []commandDiagnostic{}}
	var snapshots []artifactSnapshot
	if structured {
		snapshots = nativeArtifactSnapshots(command, output, trace)
	}
	verified := map[string]bool{}
	finish := func(status int) int {
		if !structured {
			return status
		}
		document.ExitCode = status
		if status < 0 {
			document.ExitCode = 255
		}
		document.inventory(snapshots, verified)
		return emitJSON(document, status)
	}
	fail := func(phase string, err error) int {
		fmt.Fprintln(os.Stderr, err)
		document.Reason = phase + "_error"
		document.Diagnostics = append(document.Diagnostics, commandDiagnostic{Code: "MSN001", Phase: phase, Message: err.Error(), Position: syntax.Position{File: filename, Line: 1, Column: 1}})
		return finish(1)
	}
	if command == "profile" {
		options.CPUProfile, options.HeapProfile = filepath.Join(output, "cpu.pprof"), filepath.Join(output, "heap.pprof")
		if trace {
			options.Trace = filepath.Join(output, "trace.out")
		}
	}
	go build.CurrentPin()
	result := compiler.CompileFileForBuild(filename, options, kind)
	document.SourceRoot = result.SourceRoot
	if !result.Success() {
		if !structured {
			return reportDiagnostics(result)
		}
		document.Reason = "compile_error"
		for _, issue := range result.Diagnostics {
			document.Diagnostics = append(document.Diagnostics, sourceDiagnostic(issue))
		}
		return finish(1)
	}
	if pathErr != nil {
		return fail("build", pathErr)
	}
	cache := ""
	if result.ProjectRoot != "" {
		cache = filepath.Join(result.ProjectRoot, ".ms-cache")
	}
	if command == "build" {
		if info, err := os.Stat(output); err == nil && info.IsDir() {
			fmt.Fprintf(os.Stderr, "-o %s is a directory; pass a file path (e.g. -o %s)\n", displayOutput, filepath.Join(displayOutput, "program"))
			return 2
		}
		if cache == "" {
			cache = filepath.Join(filepath.Dir(output), ".ms-cache")
		}
		if _, err := build.BuildCheckedWithType(result, output, cache, kind); err != nil {
			return fail("build", err)
		}
		verified["executable"], verified["build_metadata"] = true, true
		document.Completed = true
		if !structured {
			fmt.Println("Built", displayOutput)
		}
		return finish(0)
	}
	if err := os.Mkdir(output, 0700); err != nil {
		return fail("artifact", fmt.Errorf("profile directory must be new: %w; choose a path that does not exist with --out-dir <directory>", err))
	}
	if cache == "" {
		var err error
		cache, err = build.DefaultBuildCacheDir()
		if err != nil {
			_ = os.RemoveAll(output)
			return fail("build", err)
		}
	}
	directory, err := os.MkdirTemp("", "manuscript-run-")
	if err != nil {
		return fail("execution", err)
	}
	defer os.RemoveAll(directory)
	executable := filepath.Join(output, "program")
	if runtime.GOOS == "windows" {
		executable += ".exe"
	}
	if _, err := build.BuildCheckedWithType(result, executable, cache, kind); err != nil {
		// This invocation created the directory; a failed build must not block a retry.
		_ = os.RemoveAll(output)
		return fail("build", err)
	}
	verified["executable"], verified["build_metadata"] = true, true
	if err := writeProfileReference(output, executable, result, trace); err != nil {
		return fail("artifact", err)
	}
	verified["manifest"], verified["inspection"] = true, true
	child := exec.Command(executable, arguments...)
	child.Stdin, child.Stdout, child.Stderr = os.Stdin, os.Stdout, os.Stderr
	child.Dir = testWorkingDirectory(command, filename, result)
	var stdout *os.File
	if structured {
		stdout, err = os.Create(filepath.Join(directory, "stdout"))
		if err != nil {
			return fail("output", err)
		}
		defer stdout.Close()
		child.Stdout = stdout
	}
	runErr := runWithSignals(child)
	if structured {
		if _, err := stdout.Seek(0, io.SeekStart); err != nil {
			return fail("output", err)
		}
		captured, err := io.ReadAll(stdout)
		if err != nil {
			return fail("output", err)
		}
		document.Stdout, document.StdoutBase64 = capturedOutput(captured)
	}
	if runErr != nil {
		var exit *exec.ExitError
		if !errors.As(runErr, &exit) {
			return fail("execution", runErr)
		}
		if exit.ProcessState.Exited() {
			document.Completed = true
			document.Reason = "program_exit"
		} else {
			document.Reason = "interrupted"
		}
		return finish(exit.ExitCode())
	}
	document.Completed = true
	return finish(0)
}

func capturedOutput(output []byte) (string, string) {
	if utf8.Valid(output) {
		return string(output), ""
	}
	return "", base64.StdEncoding.EncodeToString(output)
}

func writeProfileReference(directory, executable string, result compiler.Result, trace bool) error {
	artifacts := map[string]any{"format": 1, "source_root": result.SourceRoot, "executable": filepath.Base(executable), "inspection": "inspection.json", "cpu_profile": "cpu.pprof", "heap_profile": "heap.pprof"}
	if trace {
		artifacts["trace"] = "trace.out"
	}
	manifest, err := json.MarshalIndent(artifacts, "", "  ")
	if err != nil {
		return err
	}
	if err := os.WriteFile(filepath.Join(directory, "manifest.json"), manifest, 0600); err != nil {
		return err
	}
	inspection, err := json.MarshalIndent(tooling.Inspect(result.Program), "", "  ")
	if err == nil {
		err = os.WriteFile(filepath.Join(directory, "inspection.json"), inspection, 0600)
	}
	return err
}
