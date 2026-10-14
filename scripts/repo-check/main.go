// repo-check enforces the documented dependency and native build boundaries.
package main

import (
	"bytes"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"github.com/manuscript-lang/manuscript/pkg/frontend"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
	"github.com/manuscript-lang/manuscript/scripts/internal/devtool"
	"go/ast"
	"go/format"
	"go/parser"
	"go/token"
	"gopkg.in/yaml.v3"
	"io"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

const module = "github.com/manuscript-lang/manuscript"

type policy struct {
	Dependencies    map[string][]string `json:"dependencies"`
	Pinned, Bundled []string
}
type pkg struct {
	ImportPath, Dir                              string
	Imports, GoFiles, IgnoredGoFiles, EmbedFiles []string
}

func main() {
	if err := check(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
func check() error {
	if len(os.Args) > 2 || len(os.Args) == 2 && os.Args[1] != "-format" {
		return fmt.Errorf("usage: repo-check [-format]")
	}
	if err := checkStandardSyntax(os.DirFS("pkg/stdlib"), "pkg/stdlib"); err != nil {
		return err
	}
	if err := checkNestedMatches(); err != nil {
		return err
	}

	data, err := os.ReadFile("scripts/repo-check/policy.json")
	if err != nil {
		return err
	}
	var rules policy
	if err := json.Unmarshal(data, &rules); err != nil {
		return err
	}
	command := exec.Command(devtool.Go(), "list", "-json", "./...")
	data, err = command.Output()
	if err != nil {
		return fmt.Errorf("list repository packages: %w", err)
	}
	packages := map[string]pkg{}
	decoder := json.NewDecoder(strings.NewReader(string(data)))
	for {
		var p pkg
		if err := decoder.Decode(&p); err == io.EOF {
			break
		} else if err != nil {
			return err
		}
		name := strings.TrimPrefix(p.ImportPath, module+"/")
		if p.ImportPath == module {
			name = "."
		}
		packages[name] = p
	}
	if len(os.Args) == 2 {
		return checkFormat(packages)
	}
	var issues []string
	issues = append(issues, dependencyIssues(rules, packages)...)
	hashFile, err := parser.ParseFile(token.NewFileSet(), "pkg/build/cache.go", nil, 0)
	if err != nil {
		return err
	}
	hashImports := map[string]string{}
	for _, imp := range hashFile.Imports {
		path, _ := strconv.Unquote(imp.Path.Value)
		alias := filepath.Base(path)
		if imp.Name != nil {
			alias = imp.Name.Name
		}
		hashImports[alias] = strings.TrimPrefix(path, module+"/")
	}
	hashed := map[string]bool{}
	ast.Inspect(hashFile, func(n ast.Node) bool {
		if s, ok := n.(*ast.SelectorExpr); ok && (s.Sel.Name == "ImplementationSources" || s.Sel.Name == "Sources") {
			if id, ok := s.X.(*ast.Ident); ok {
				hashed[hashImports[id.Name]] = true
			}
		}
		return true
	})
	hashed["pkg/build"] = true // Its unqualified ImplementationSources is in the same package.
	for _, name := range rules.Pinned {
		if !hashed[name] {
			issues = append(issues, "implementation hash omits "+name)
		}
		if name == "pkg/stdlib" {
			continue
		} // Only the authoritative .ms and binding data enter native identity.
		p := packages[name]
		embedded := map[string]bool{}
		for _, path := range p.EmbedFiles {
			embedded[path] = true
		}
		entries, err := os.ReadDir(p.Dir)
		if err != nil {
			return err
		}
		for _, entry := range entries {
			filename := entry.Name()
			if entry.IsDir() || !strings.HasSuffix(filename, ".go") || strings.HasSuffix(filename, "_test.go") {
				continue
			}
			// Embed carriers declare the input filesystem; they aren't emitted runtime code.
			content, err := os.ReadFile(filepath.Join(p.Dir, filename))
			if err != nil {
				return err
			}
			if strings.Contains(string(content), "//go:embed") {
				continue
			}
			if !embedded[filename] {
				issues = append(issues, name+" source is missing from its embedded inputs: "+filename)
			}
		}
	}
	embedded := map[string]bool{}
	for _, path := range packages["."].EmbedFiles {
		embedded[path] = true
	}
	for _, name := range rules.Bundled {
		err := filepath.WalkDir(name, func(path string, e fs.DirEntry, err error) error {
			if err != nil {
				return err
			}
			if !e.IsDir() && strings.HasSuffix(path, ".go") && !strings.HasSuffix(path, "_test.go") && !embedded[filepath.ToSlash(path)] {
				issues = append(issues, "native dependency bundle omits "+path)
			}
			return nil
		})
		if err != nil {
			return err
		}
	}
	for _, path := range []string{".github/workflows/cicd.yml", ".github/workflows/release.yml"} {
		workflow, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		if err := checkWorkflowTriggers(workflow); err != nil {
			issues = append(issues, path+": "+err.Error())
		}
	}
	// A stage may split its kinds across several functions while expressions
	// move into the IR; together they must handle every kind.
	for _, stage := range []struct {
		handlers []kindHandler
		kinds    []string
	}{
		{[]kindHandler{{"pkg/lower/lower_statements.go", "statement"}}, syntax.StatementKinds()},
		{[]kindHandler{{"pkg/lower/lower_expressions.go", "expressionValue"}, {"pkg/ir/elaborate.go", "Value"}}, syntax.ExpressionKinds()},
		{[]kindHandler{{"pkg/checker/checker.go", "checkStatement"}}, syntax.StatementKinds()},
		{[]kindHandler{{"pkg/checker/expressions.go", "infer"}}, syntax.ExpressionKinds()},
	} {
		missing, err := missingKinds(stage.handlers, stage.kinds)
		if err != nil {
			return err
		}
		for _, kind := range missing {
			issues = append(issues, stage.handlers[0].path+" "+stage.handlers[0].function+" does not handle "+kind)
		}
	}

	version, err := os.ReadFile(".go-version")
	if err != nil {
		return err
	}
	pin := strings.TrimSpace(string(version))
	checksumData, err := os.ReadFile("scripts/toolchains.sha256")
	if err != nil {
		return err
	}
	archives := map[string]bool{}
	for _, line := range strings.Split(strings.TrimSpace(string(checksumData)), "\n") {
		fields := strings.Fields(line)
		if len(fields) != 2 {
			issues = append(issues, "invalid SDK checksum line")
			continue
		}
		bytes, err := hex.DecodeString(fields[0])
		if err != nil || len(bytes) != 32 {
			issues = append(issues, "invalid SHA-256 for "+fields[1])
		}
		if archives[fields[1]] {
			issues = append(issues, "duplicate SDK archive "+fields[1])
		}
		archives[fields[1]] = true
	}
	for _, target := range []string{"linux-amd64.tar.gz", "linux-arm64.tar.gz", "darwin-amd64.tar.gz", "darwin-arm64.tar.gz", "windows-amd64.zip", "windows-arm64.zip"} {
		if !archives["go"+pin+"."+target] {
			issues = append(issues, "SDK pin lacks checksum for "+target)
		}
	}
	if len(archives) != 6 {
		issues = append(issues, "SDK catalog must contain exactly six pinned archives")
	}
	moduleData, err := os.ReadFile("go.mod")
	if err != nil {
		return err
	}
	parts := strings.Split(pin, ".")
	if len(parts) != 3 || !strings.Contains(string(moduleData), "\ngo "+parts[0]+"."+parts[1]+".0\n") {
		issues = append(issues, "module Go language version disagrees with pinned SDK")
	}

	sort.Strings(issues)
	if len(issues) > 0 {
		return fmt.Errorf("repository invariants:\n- %s", strings.Join(issues, "\n- "))
	}
	fmt.Println("Package boundaries, implementation pins, native bundles, and release triggers agree.")
	return nil
}

// Required workflows must report on every PR and on the queue's combined commit.
func checkWorkflowTriggers(data []byte) error {
	var workflow struct {
		On map[string]struct {
			Paths       []string `yaml:"paths"`
			PathsIgnore []string `yaml:"paths-ignore"`
			Types       []string `yaml:"types"`
		} `yaml:"on"`
	}
	if err := yaml.Unmarshal(data, &workflow); err != nil {
		return fmt.Errorf("parse workflow: %w", err)
	}
	pr, ok := workflow.On["pull_request"]
	if !ok || len(pr.Paths) != 0 || len(pr.PathsIgnore) != 0 {
		return fmt.Errorf("required checks must run on every pull request without path filters")
	}
	queue, ok := workflow.On["merge_group"]
	if !ok || len(queue.Types) != 1 || queue.Types[0] != "checks_requested" {
		return fmt.Errorf("required checks must run on merge_group checks_requested")
	}
	return nil
}

// Validate the working-tree files with the ordinary strict frontend before
// loading checker/runtime packages. Report syntax errors directly, rather than
// relying on a standard-loader initialization panic to fail another check.
func checkStandardSyntax(sources fs.FS, directory string) error {
	entries, err := fs.ReadDir(sources, ".")
	if err != nil {
		return fmt.Errorf("read standard declarations: %w", err)
	}
	var issues []string
	for _, entry := range entries {
		if entry.IsDir() || filepath.Ext(entry.Name()) != ".ms" {
			continue
		}
		source, err := fs.ReadFile(sources, entry.Name())
		if err != nil {
			return fmt.Errorf("read standard declaration %s: %w", entry.Name(), err)
		}
		_, diagnostics := frontend.Parse(filepath.Join(directory, entry.Name()), string(source), false)
		for _, issue := range diagnostics {
			issues = append(issues, issue.Error())
		}
	}
	if len(issues) > 0 {
		return fmt.Errorf("invalid standard-library syntax:\n- %s", strings.Join(issues, "\n- "))
	}
	return nil
}
func contains(values []string, value string) bool {
	for _, v := range values {
		if v == value {
			return true
		}
	}
	return false
}

func dependencyIssues(rules policy, packages map[string]pkg) []string {
	var issues []string
	for owner, allowed := range rules.Dependencies {
		p, ok := packages[owner]
		if !ok {
			issues = append(issues, "missing governed package "+owner)
			continue
		}
		for _, dependency := range p.Imports {
			if dependency != module && !strings.HasPrefix(dependency, module+"/") {
				continue
			}
			name := strings.TrimPrefix(dependency, module+"/")
			if dependency == module {
				name = "."
			}
			if !contains(allowed, name) {
				issues = append(issues, owner+" imports forbidden package "+name)
			}
		}
	}
	for name, p := range packages {
		if strings.HasPrefix(name, "scripts/") || strings.HasPrefix(name, "tests/") || name == "." {
			continue
		}
		if _, ok := rules.Dependencies[name]; !ok {
			issues = append(issues, "package needs an explicit dependency policy: "+name)
		}
		if name == "pkg/runtime" || strings.HasPrefix(name, "internal/") && name != "internal/cli" {
			continue
		}
		for _, dependency := range p.Imports {
			if strings.Contains(dependency, ".") && dependency != module && !strings.HasPrefix(dependency, module+"/") {
				issues = append(issues, name+" has an external dependency: "+dependency)
			}
		}
	}
	return issues
}

// kindHandler names a function whose switch on a syntax Kind handles kinds.
type kindHandler struct{ path, function string }

func missingKinds(handlers []kindHandler, kinds []string) ([]string, error) {
	constants := map[string]string{}
	definitions, err := parser.ParseFile(token.NewFileSet(), "pkg/syntax/kinds.go", nil, 0)
	if err != nil {
		return nil, err
	}
	ast.Inspect(definitions, func(node ast.Node) bool {
		if spec, ok := node.(*ast.ValueSpec); ok && len(spec.Names) == 1 && len(spec.Values) == 1 {
			if value, ok := spec.Values[0].(*ast.BasicLit); ok && value.Kind == token.STRING {
				constants[spec.Names[0].Name], _ = strconv.Unquote(value.Value)
			}
		}
		return true
	})
	seen := map[string]bool{}
	for _, handler := range handlers {
		file, err := parser.ParseFile(token.NewFileSet(), handler.path, nil, 0)
		if err != nil {
			return nil, err
		}
		for _, declaration := range file.Decls {
			fn, ok := declaration.(*ast.FuncDecl)
			if !ok || fn.Name.Name != handler.function {
				continue
			}
			ast.Inspect(fn.Body, func(node ast.Node) bool {
				branch, ok := node.(*ast.SwitchStmt)
				if !ok {
					return true
				}
				tag, ok := branch.Tag.(*ast.SelectorExpr)
				if !ok || tag.Sel.Name != "Kind" {
					return true
				}
				for _, statement := range branch.Body.List {
					for _, label := range statement.(*ast.CaseClause).List {
						switch value := label.(type) {
						case *ast.BasicLit:
							key, _ := strconv.Unquote(value.Value)
							seen[key] = true
						case *ast.SelectorExpr:
							seen[constants[value.Sel.Name]] = true
						}
					}
				}
				return true
			})
		}
	}
	var missing []string
	for _, kind := range kinds {
		if !seen[kind] {
			missing = append(missing, kind)
		}
	}
	return missing, nil
}

func checkFormat(packages map[string]pkg) error {
	var changed []string
	for _, p := range packages {
		entries, err := os.ReadDir(p.Dir)
		if err != nil {
			return err
		}
		for _, entry := range entries {
			if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".go") {
				continue
			}
			name := filepath.Join(p.Dir, entry.Name())
			source, err := os.ReadFile(name)
			if err != nil {
				return err
			}
			formatted, err := format.Source(source)
			if err != nil {
				return fmt.Errorf("format %s: %w", name, err)
			}
			if !bytes.Equal(source, formatted) {
				changed = append(changed, name)
			}
		}
	}
	sort.Strings(changed)
	if len(changed) > 0 {
		return fmt.Errorf("run make fmt for:\n%s", strings.Join(changed, "\n"))
	}
	return nil
}
