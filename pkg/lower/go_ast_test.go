package lower

import (
	"bytes"
	"go/ast"
	"go/format"
	"go/parser"
	"go/token"
	"reflect"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/checker"
)

func TestGoASTSourceMarkersAttachToStatements(t *testing.T) {
	source := `fn value(flag: Bool = true) -> Int:
    while flag:
        let nested = fn() -> Int:
            return 2
        if nested() > 0: break
    return 0
`
	checked := analyzeSource("mapped.ms", source)
	if !checked.Success() {
		t.Fatal(checked.Diagnostics)
	}
	optimized := optimize(checked.Program)
	g := &generator{program: checked.Program, booleans: optimized.booleans, captures: map[*checker.Binding]string{}, typed: map[*checker.Binding]string{}}
	file := g.file("mapped.ms", Options{})
	var targets []string
	ast.Inspect(file, func(node ast.Node) bool {
		if label, ok := node.(*ast.LabeledStmt); ok {
			if pos, ok := g.sourceLines[label.Label.Name]; ok {
				var text bytes.Buffer
				if err := format.Node(&text, token.NewFileSet(), label.Stmt); err != nil {
					t.Fatal(err)
				}
				// Nested actual loop labels are allowed between the directive and loop.
				targets = append(targets, sourceDirective(pos)+"\n"+strings.TrimSpace(strings.Split(text.String(), "\n")[0]))
			}
		}
		return true
	})
	printed, err := g.printGo(file)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(printed, "manuscriptSourceLine") {
		t.Fatal("source marker escaped printer")
	}
	lines := strings.Split(printed, "\n")
	var actual []string
	for i, line := range lines {
		if strings.HasPrefix(line, "//line ") {
			actual = append(actual, line+"\n"+strings.TrimSpace(lines[i+1]))
		}
	}
	if !reflect.DeepEqual(targets, actual) {
		t.Fatalf("source markers moved away from statements\nwant %q\ngot %q", targets, actual)
	}
	// A second print must neither mutate the tree nor consume its source map.
	repeated, err := g.printGo(file)
	if err != nil || repeated != printed {
		t.Fatal("printing mutated the tree", err)
	}
	fset := token.NewFileSet()
	parsed, err := parser.ParseFile(fset, "generated.go", printed, 0)
	if err != nil {
		t.Fatal(err)
	}
	returns := map[string]bool{}
	ast.Inspect(parsed, func(node ast.Node) bool {
		if stmt, ok := node.(*ast.ReturnStmt); ok {
			returns[fset.Position(stmt.Pos()).String()] = true
		}
		return true
	})
	if !returns["mapped.ms:4"] || !returns["mapped.ms:6"] {
		t.Fatalf("return lines lost: %v", returns)
	}
}

func sourceDirectives(source string) []string {
	var directives []string
	for _, line := range strings.Split(source, "\n") {
		if strings.HasPrefix(line, "//line ") {
			directives = append(directives, line)
		}
	}
	return directives
}
