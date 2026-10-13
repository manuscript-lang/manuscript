// mkgotoolchain copies the pinned SDK's compiler, linker, and assembler into
// internal/gotoolchain so the ms binary can run them without a Go installation.
// Go forbids importing cmd/... and std internal packages from another module,
// so the copy rewrites those import paths beneath this module. Run it after
// changing .go-version; it replaces the previous copy of the cmd and internal
// trees, leaving the hand-written package at internal/gotoolchain intact.
package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"go/ast"
	"go/format"
	"go/parser"
	"go/token"
	"io"
	"maps"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"sort"
	"strconv"
	"strings"

	"github.com/manuscript-lang/manuscript/scripts/internal/devtool"
)

const (
	module = "github.com/manuscript-lang/manuscript/internal/gotoolchain"
	output = "internal/gotoolchain"
)

// Tool entry points become importable packages exposing Main.
var tools = map[string]string{"cmd/compile": "compile", "cmd/link": "link", "cmd/asm": "asm"}

// Telemetry is a no-op in the copy; its bootstrap variant has no dependencies.
const telemetry = "cmd/internal/telemetry/counter"

// Release targets whose build constraints must all be satisfiable.
var targets = []string{"linux/amd64", "linux/arm64", "darwin/amd64", "darwin/arm64", "windows/amd64", "windows/arm64"}

type listed struct {
	ImportPath     string
	Dir            string
	Standard       bool
	Imports        []string
	GoFiles        []string
	SFiles         []string
	HFiles         []string
	IgnoredGoFiles []string
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func run() error {
	goTool := devtool.Go()
	rootOutput, err := exec.Command(goTool, "env", "GOROOT").Output()
	if err != nil {
		return fmt.Errorf("locate pinned SDK: %w", err)
	}
	root := strings.TrimSpace(string(rootOutput))
	packages, err := listPackages(goTool, root)
	if err != nil {
		return err
	}
	copied := closure(packages)
	// The package at the root of output is maintained by hand.
	for _, generated := range []string{"cmd", "internal"} {
		if err := os.RemoveAll(filepath.Join(output, generated)); err != nil {
			return err
		}
	}
	for _, path := range slices.Sorted(maps.Keys(copied)) {
		if err := copyPackage(packages[path], copied); err != nil {
			return fmt.Errorf("%s: %w", path, err)
		}
	}
	if err := copyFlag(root, copied); err != nil {
		return err
	}
	for _, name := range []string{"LICENSE", "PATENTS"} {
		data, err := os.ReadFile(filepath.Join(root, name))
		if err != nil {
			return err
		}
		if err := os.WriteFile(filepath.Join(output, name), data, 0644); err != nil {
			return err
		}
	}
	version, err := os.ReadFile(filepath.Join(root, "VERSION"))
	if err != nil {
		return err
	}
	first, _, _ := strings.Cut(string(version), "\n")
	return os.WriteFile(filepath.Join(output, "VERSION"), []byte(first+"\n"), 0644)
}

// listPackages lists the tools' dependencies for every release target,
// merging each package's imports across targets.
func listPackages(goTool, root string) (map[string]*listed, error) {
	packages := map[string]*listed{}
	for _, target := range targets {
		goos, goarch, _ := strings.Cut(target, "/")
		command := exec.Command(goTool, "list", "-pgo=off", "-deps", "-json", "cmd/compile", "cmd/link", "cmd/asm")
		command.Dir = filepath.Join(root, "src", "cmd")
		command.Env = append(os.Environ(), "GOOS="+goos, "GOARCH="+goarch, "CGO_ENABLED=0", "GOFLAGS=", "GOTOOLCHAIN=local", "GOENV=off")
		data, err := command.Output()
		if err != nil {
			if failure, ok := err.(*exec.ExitError); ok {
				return nil, fmt.Errorf("list %s tools: %w\n%s", target, err, failure.Stderr)
			}
			return nil, err
		}
		decoder := json.NewDecoder(bytes.NewReader(data))
		for {
			var pkg listed
			if err := decoder.Decode(&pkg); err == io.EOF {
				break
			} else if err != nil {
				return nil, err
			}
			if previous := packages[pkg.ImportPath]; previous != nil {
				previous.Imports = append(previous.Imports, pkg.Imports...)
			} else {
				packages[pkg.ImportPath] = &pkg
			}
		}
	}
	return packages, nil
}

// closure selects every cmd package reachable from the tools, plus the std
// internal packages that copied code imports. Public std packages stay shared.
func closure(packages map[string]*listed) map[string]bool {
	copied := map[string]bool{}
	var visit func(string)
	visit = func(path string) {
		if copied[path] || !copyable(path) {
			return
		}
		copied[path] = true
		if path == telemetry {
			return
		}
		for _, imported := range packages[path].Imports {
			visit(imported)
		}
	}
	for tool := range tools {
		visit(tool)
	}
	return copied
}

func copyable(path string) bool {
	return strings.HasPrefix(path, "cmd/") && !strings.HasPrefix(path, "cmd/vendor/") || strings.HasPrefix(path, "internal/")
}

func target(path string) string {
	if name, ok := tools[path]; ok {
		return filepath.Join(output, "cmd", name)
	}
	return filepath.Join(output, filepath.FromSlash(path))
}

func copyPackage(pkg *listed, copied map[string]bool) error {
	directory := target(pkg.ImportPath)
	if err := os.MkdirAll(directory, 0755); err != nil {
		return err
	}
	files := map[string]bool{}
	for _, group := range [][]string{pkg.GoFiles, pkg.SFiles, pkg.HFiles} {
		for _, name := range group {
			files[name] = true
		}
	}
	// Files for other targets or build tags (such as race) are kept when
	// their imports are available in the copy.
	optional := map[string]bool{}
	for _, name := range pkg.IgnoredGoFiles {
		files[name] = true
		optional[name] = true
	}
	if pkg.ImportPath == telemetry {
		files = map[string]bool{"counter_bootstrap.go": true}
	}
	names := make([]string, 0, len(files))
	for name := range files {
		// Test assembly defines symbols by absolute name, which would clash
		// with the standard package the copy shadows.
		if !strings.HasSuffix(name, "_test.go") && !strings.HasSuffix(name, "_test.s") {
			names = append(names, name)
		}
	}
	sort.Strings(names)
	for _, name := range names {
		data, err := os.ReadFile(filepath.Join(pkg.Dir, name))
		if err != nil {
			return err
		}
		if strings.HasSuffix(name, ".go") {
			data, err = rewrite(pkg.ImportPath, name, data, copied, optional[name])
			if err != nil {
				return err
			}
			if data == nil {
				continue
			}
		}
		if err := os.WriteFile(filepath.Join(directory, name), data, 0644); err != nil {
			return err
		}
	}
	return nil
}

// rewrite moves copied imports beneath this module and turns tool mains into
// library entry points. It returns nil for generator files and for optional
// files whose imports were not copied.
func rewrite(path, name string, data []byte, copied map[string]bool, optional bool) ([]byte, error) {
	files := token.NewFileSet()
	file, err := parser.ParseFile(files, name, data, parser.ParseComments)
	if err != nil {
		return nil, err
	}
	for _, group := range file.Comments {
		if group.Pos() >= file.Package {
			break
		}
		for _, comment := range group.List {
			if strings.HasPrefix(comment.Text, "//go:build") && strings.Contains(comment.Text, "ignore") {
				return nil, nil
			}
		}
	}
	if path == telemetry {
		// Always select the dependency-free variant.
		for _, group := range file.Comments {
			for _, comment := range group.List {
				if strings.HasPrefix(comment.Text, "//go:build") {
					comment.Text = "//"
				}
			}
		}
	}
	for _, spec := range file.Imports {
		imported, err := strconv.Unquote(spec.Path.Value)
		if err != nil {
			return nil, err
		}
		if imported == "flag" {
			spec.Path.Value = strconv.Quote(module + "/internal/flag")
		} else if copied[imported] {
			replacement := module + "/" + imported
			if tool, ok := tools[imported]; ok {
				replacement = module + "/cmd/" + tool
			}
			spec.Path.Value = strconv.Quote(replacement)
		} else if copyable(imported) && optional {
			return nil, nil
		} else if copyable(imported) {
			return nil, fmt.Errorf("%s imports uncopied %s", name, imported)
		}
	}
	if tool, ok := tools[path]; ok && file.Name.Name == "main" {
		file.Name.Name = tool
		for _, declaration := range file.Decls {
			if function, ok := declaration.(*ast.FuncDecl); ok && function.Recv == nil && function.Name.Name == "main" {
				function.Name.Name = "Main"
			}
		}
	}
	var buffer bytes.Buffer
	buffer.WriteString("// Code copied from the Go distribution by scripts/mkgotoolchain; DO NOT EDIT.\n\n")
	if err := format.Node(&buffer, files, file); err != nil {
		return nil, err
	}
	return buffer.Bytes(), nil
}

// The tools register flags in package initializers, and the linker and
// assembler both define -o. They therefore share a private copy of package
// flag in which only the running tool's own registrations reach CommandLine.
func copyFlag(root string, copied map[string]bool) error {
	source := filepath.Join(root, "src", "flag", "flag.go")
	data, err := os.ReadFile(source)
	if err != nil {
		return err
	}
	// Route every package-level use of CommandLine through commandLine.
	if !bytes.Contains(data, []byte("CommandLine.")) {
		return fmt.Errorf("%s: no CommandLine uses to route", source)
	}
	data = bytes.ReplaceAll(data, []byte("CommandLine."), []byte("commandLine()."))
	data, err = rewrite("flag", "flag.go", data, copied, false)
	if err != nil {
		return err
	}
	directory := filepath.Join(output, "internal", "flag")
	if err := os.MkdirAll(directory, 0755); err != nil {
		return err
	}
	if err := os.WriteFile(filepath.Join(directory, "flag.go"), data, 0644); err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(directory, "tool.go"), []byte(flagSelection), 0644)
}

const flagSelection = `// Code generated by scripts/mkgotoolchain; DO NOT EDIT.

package flag

import (
	"os"
	"runtime"
	"strings"
)

// activeTool names the copied tool this process runs, if any.
var activeTool = os.Getenv("MANUSCRIPT_GO_TOOL")

// commandLine returns CommandLine, or a new discarded set when the call
// comes from a copied tool other than the one this process runs.
func commandLine() *FlagSet {
	callers := make([]uintptr, 32)
	frames := runtime.CallersFrames(callers[:runtime.Callers(2, callers)])
	for {
		frame, more := frames.Next()
		if tool := owner(frame.Function); tool != "" && tool != activeTool {
			return NewFlagSet(tool, ContinueOnError)
		}
		if !more {
			return CommandLine
		}
	}
}

// owner names the copied tool whose package tree declares function, if any.
func owner(function string) string {
	_, rest, found := strings.Cut(function, "/gotoolchain/cmd/")
	if !found {
		return ""
	}
	tool, _, _ := strings.Cut(rest, "/")
	tool, _, _ = strings.Cut(tool, ".")
	switch tool {
	case "compile", "link", "asm":
		return tool
	}
	return "" // shared cmd/internal packages
}
`
