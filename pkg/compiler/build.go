package compiler

import (
	"bytes"
	"fmt"
	msruntime "github.com/manuscript-lang/manuscript/pkg/runtime"
	"go/ast"
	"go/build/constraint"
	"go/format"
	"go/parser"
	"go/scanner"
	"go/token"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

// Standalone combines checked Go and its embedded runtime into one source file.
func Standalone(source string) (string, error) {
	// Rewrite the generated runtime qualifier outside strings using Go tokens.
	fset := token.NewFileSet()
	file := fset.AddFile("generated", -1, len(source))
	var scan scanner.Scanner
	scan.Init(file, []byte(source), nil, 0)
	var out strings.Builder
	at := 0
	for {
		position, kind, literal := scan.Scan()
		if kind == token.EOF {
			break
		}
		offset := file.Offset(position)
		if kind == token.IDENT && literal == "rt" {
			next, kind, _ := scan.Scan()
			if kind != token.PERIOD {
				continue
			}
			out.WriteString(source[at:offset])
			at = file.Offset(next) + 1
		}
	}
	out.WriteString(source[at:])
	parsed, err := parser.ParseFile(fset, "generated.go", out.String(), parser.ParseComments)
	if err != nil {
		return "", err
	}
	imports := map[string]*ast.ImportSpec{}
	var declarations []ast.Decl
	add := func(file *ast.File) {
		for _, decl := range file.Decls {
			if group, ok := decl.(*ast.GenDecl); ok && group.Tok == token.IMPORT {
				for _, s := range group.Specs {
					spec := s.(*ast.ImportSpec)
					path, _ := strconv.Unquote(spec.Path.Value)
					if path != "github.com/manuscript-lang/manuscript/pkg/runtime" {
						imports[path] = spec
					}
				}
			} else {
				declarations = append(declarations, decl)
			}
		}
	}
	add(parsed)
	entries, err := msruntime.Sources.ReadDir(".")
	if err != nil {
		return "", err
	}
	for _, entry := range entries {
		data, err := msruntime.Sources.ReadFile(entry.Name())
		if err != nil {
			return "", err
		}
		file, err := parser.ParseFile(fset, entry.Name(), data, parser.ParseComments)
		if err != nil {
			return "", err
		}
		// Emitted programs carry the full runtime, so omit lean-only files.
		if !fullRuntimeFile(file) {
			continue
		}
		file.Comments = nil
		add(file)
	}
	paths := []string{}
	for path := range imports {
		paths = append(paths, path)
	}
	sort.Strings(paths)
	group := &ast.GenDecl{Tok: token.IMPORT, Lparen: 1}
	for _, path := range paths {
		group.Specs = append(group.Specs, imports[path])
	}
	merged := &ast.File{Comments: parsed.Comments, Name: ast.NewIdent("main"), Decls: append([]ast.Decl{group}, declarations...)}
	var buffer bytes.Buffer
	if err := format.Node(&buffer, fset, merged); err != nil {
		return "", err
	}
	formatted, err := format.Source(buffer.Bytes())
	return string(formatted), err
}

// Build invokes the selected Go toolchain without obtaining external dependencies.
func Build(source, output string) error { return BuildWithType(source, output, Release) }

// BuildWithType builds unchecked generated source with an explicit native build type.
func BuildWithType(source, output string, kind BuildType) error {
	kind, err := ParseBuildType(string(kind))
	if err != nil {
		return err
	}
	return buildNative(source, output, kind, nil)
}

func buildNative(source, output string, kind BuildType, tags []string) error {
	root, err := workspaceRoot()
	if err != nil {
		return err
	}
	output, err = filepath.Abs(output)
	if err != nil {
		return err
	}
	dir, err := applicationDir(root, source, kind, tags)
	if err != nil {
		return err
	}
	packagePath := workspaceModule + "/apps/" + filepath.Base(dir)
	imports, importErr := sourceImports(source)
	key, keyErr := replayKey(kind, tags)
	replayable := importErr == nil && keyErr == nil
	if replayable {
		if profile, ok := loadReplay(root, key, imports); ok {
			if profile.replay(dir, packagePath, output) == nil {
				return nil
			}
			// Go may reuse its cached compilation of this exact source, leaving
			// nothing to capture; do not retry a failing replay meanwhile.
			os.Remove(replayPath(root, key))
		}
		if err := captureBuild(root, key, dir, packagePath, imports, output, kind, tags); err == nil {
			return nil
		}
		// Report diagnostics from an ordinary build without command tracing.
	}
	return goBuild(dir, output, kind, tags)
}

func goBuild(dir, output string, kind BuildType, tags []string) error {
	arguments := append(buildArguments(kind, tags), kind.nativeFlags()...)
	// Build the application package, rather than a file with the synthetic
	// command-line-arguments identity. Internal native adapters must resolve
	// under the module identity even when the workspace path has symlinked
	// ancestors (as on macOS) or platform-specific path spelling.
	arguments = append(arguments, "-o", output, ".")
	command, err := goCommand(arguments...)
	if err != nil {
		return err
	}
	command.Dir = dir
	data, err := command.CombinedOutput()
	if err != nil {
		hint := ""
		if bytes.Contains(data, []byte("requires go >=")) {
			hint = "\nhint: the bundled toolchain is too old for this build; update ms"
		} else if bytes.Contains(data, []byte("cannot find package")) || bytes.Contains(data, []byte("no required module provides")) {
			hint = "\nhint: the build could not find a dependency, which usually means a stale cache; remove the MANUSCRIPT_CACHE_DIR directory and retry"
		} else {
			hint = "\nhint: if ms check passes this is likely a Manuscript compiler bug, not a mistake in your source; report it with the output above and the .ms source that triggers it"
		}
		return fmt.Errorf("Go build failed while compiling the generated program: %w\n%s%s", err, data, hint)
	}
	return nil
}

// captureBuild runs go build with command tracing and records a replay profile.
func captureBuild(root, key, dir, packagePath string, imports []string, output string, kind BuildType, tags []string) error {
	arguments := append(append(buildArguments(kind, tags), "-x", "-work"), kind.nativeFlags()...)
	command, err := goCommand(append(arguments, "-o", output, ".")...)
	if err != nil {
		return err
	}
	command.Dir = dir
	trace, err := command.CombinedOutput()
	if work := traceWork(trace); work != "" {
		defer os.RemoveAll(work)
	}
	if err != nil {
		return err
	}
	if profile, ok := captureReplay(trace, dir, packagePath, imports); ok {
		saveReplay(root, key, profile)
	}
	return nil
}

func buildArguments(kind BuildType, tags []string) []string {
	arguments := []string{"build", "-mod=vendor", "-buildvcs=false"}
	if len(tags) > 0 {
		arguments = append(arguments, "-tags="+strings.Join(tags, ","))
	}
	return arguments
}

// fullRuntimeFile reports whether a runtime file's build constraint holds
// without the lean runtime tag.
func fullRuntimeFile(file *ast.File) bool {
	for _, group := range file.Comments {
		if group.Pos() >= file.Package {
			break
		}
		for _, comment := range group.List {
			if expression, err := constraint.Parse(comment.Text); err == nil {
				return expression.Eval(func(tag string) bool { return false })
			}
		}
	}
	return true
}
