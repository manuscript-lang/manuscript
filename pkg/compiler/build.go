package compiler

import (
	"bytes"
	"fmt"
	"github.com/manuscript-lang/manuscript/internal/gotoolchain"
	msruntime "github.com/manuscript-lang/manuscript/pkg/runtime"
	"go/ast"
	"go/build/constraint"
	"go/format"
	"go/parser"
	"go/scanner"
	"go/token"
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

// Build compiles generated source natively without obtaining external dependencies.
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
	goroot, environment, native := nativeToolchain()
	if !native {
		return goBuild(dir, output, kind, tags)
	}
	cache, err := archiveCache()
	if err != nil {
		return err
	}
	gcflags, ldflags, trimpath := kind.goFlags()
	err = gotoolchain.Build(gotoolchain.Config{
		GOROOT: goroot, ModuleRoot: root, ModulePath: workspaceModule,
		Dir: dir, ImportPath: workspaceModule + "/apps/" + filepath.Base(dir), Tags: tags,
		GCFlags: gcflags, LDFlags: ldflags, Trimpath: trimpath,
		Cache: cache, Environment: environment, Output: output,
	})
	if err != nil {
		return fmt.Errorf("Go build failed: %w", err)
	}
	return nil
}

// goBuild runs an installed go command whose release differs from ms's
// built-in Go tools.
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
		return fmt.Errorf("Go build failed: %w\n%s", err, data)
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
