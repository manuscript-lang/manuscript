package lower

import (
	"fmt"
	"go/ast"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func TestSourceDirectiveFilenames(t *testing.T) {
	for _, filename := range []string{"", "source.ms", "folder/a b.ms", `C:\source\main.ms`, "unicodé/λ.ms", "bad\r\nname\n.ms"} {
		for _, line := range []int{0, 1, 123, -1} {
			t.Run(fmt.Sprintf("%q/%d", filename, line), func(t *testing.T) {
				t.Parallel()
				want := fmt.Sprintf("//line %s:%d", strings.ReplaceAll(strings.ReplaceAll(filename, "\n", "_"), "\r", "_"), line)
				if got := sourceDirective(syntax.Position{File: filename, Line: line}); got != want {
					t.Fatalf("source directive = %q, want %q", got, want)
				}
			})
		}
	}
}

func TestPrintGoRejectsLostOrDuplicateMarkers(t *testing.T) {
	for _, count := range []int{0, 2} {
		t.Run(fmt.Sprint(count), func(t *testing.T) {
			g := newGen(nil)
			g.sourceLines["marker"] = syntax.Position{File: "source.ms", Line: 9}
			var body []ast.Stmt
			for range count {
				body = append(body, &ast.LabeledStmt{Label: ident("marker"), Stmt: evaluated(call(ident("work")))})
			}
			file := &ast.File{Name: ident("main"), Decls: []ast.Decl{
				&ast.FuncDecl{Name: ident("main"), Type: functionType(nil, nil), Body: block(body...)},
			}}
			_, err := g.printGo(file)
			want := "lost generated source directives"
			if count == 2 {
				want = "duplicate generated source marker"
			}
			if err == nil || !strings.Contains(err.Error(), want) {
				t.Fatalf("printing %d markers: got %v, want %s", count, err, want)
			}
		})
	}
}
