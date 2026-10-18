package lsp

import (
	"fmt"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func referenceDocumentation(source string, decl *syntax.Declaration) string {
	lines := strings.Split(source, "\n")
	var notes []string
	for line := decl.Pos.Line - 2; line >= 0; line-- {
		text := strings.TrimSpace(lines[line])
		if !strings.HasPrefix(text, "#") {
			break
		}
		notes = append([]string{strings.TrimSpace(strings.TrimPrefix(text, "#"))}, notes...)
	}
	return strings.TrimSpace(strings.Join(notes, "\n"))
}

func TestDeclarationDocumentationOriginalSource(t *testing.T) {
	for _, ending := range []string{"\n", "\r\n"} {
		source := strings.ReplaceAll("# α😀 heading\n#\n# second line\nfn documented() Int: 1\n# detached\n\nfn blank() Int: 2\n# ordinary\nfn first() Int: 3\nfn bare() Int: 4\n# neighboring recovered declaration\nfn neighbor() Int: 5\nfn broken(\n", "\n", ending)
		d := document{URI: "file:///documentation.ms", Text: source}
		result := compiler.CompileSource("/documentation.ms", source, compiler.Options{AnalyzeOnly: true, Recover: true})
		if len(result.Diagnostics) == 0 || result.Program == nil {
			t.Fatal("malformed recovery fixture must retain declarations and diagnostics")
		}
		m := module(result, d)
		if m == nil {
			t.Fatal("missing recovered module")
		}
		want := map[string]string{"documented": "α😀 heading\n\nsecond line", "blank": "", "first": "ordinary", "bare": "", "neighbor": "neighboring recovered declaration"}
		for _, decl := range m.Declarations {
			got := declarationDocumentation(result, decl)
			if reference := referenceDocumentation(source, decl); got != reference {
				t.Fatalf("%q line=%d offset=%d got=%q original=%q", decl.Name, decl.Pos.Line, decl.Pos.Offset, got, reference)
			}
			if expected, ok := want[decl.Name]; ok {
				if got != expected {
					t.Fatalf("%q got=%q want=%q", decl.Name, got, expected)
				}
				delete(want, decl.Name)
			}
		}
		if len(want) != 0 {
			t.Fatalf("recovery lost declarations: %v", want)
		}
	}
}

func TestDeclarationDocumentationUsesCheckedStandardSource(t *testing.T) {
	result := compiler.Result{Program: &checker.Program{}}
	checked := 0
	for _, m := range checker.StandardModules() {
		var check func(*syntax.Declaration)
		check = func(decl *syntax.Declaration) {
			want := referenceDocumentation(m.Source, decl)
			if got := declarationDocumentation(result, decl); got != want {
				t.Fatalf("%s %s got=%q want=%q", m.File, decl.Name, got, want)
			}
			if want != "" {
				checked++
			}
			for _, method := range decl.Methods {
				check(method)
			}
		}
		for _, decl := range m.Declarations {
			check(decl)
		}
	}
	if checked == 0 {
		t.Fatal("standard fixture has no documentation to verify")
	}
	if got := declarationDocumentation(result, nil); got != "" {
		t.Fatal(got)
	}
}

func BenchmarkDeclarationDocumentation(b *testing.B) {
	for _, n := range []int{1000, 2000, 4000} {
		b.Run(fmt.Sprint(n), func(b *testing.B) {
			var source strings.Builder
			decls := make([]*syntax.Declaration, 0, n)
			for i := 0; i < n; i++ {
				fmt.Fprintf(&source, "# documentation %d\n", i)
				decls = append(decls, &syntax.Declaration{Pos: syntax.Position{File: "scale.ms", Offset: source.Len(), Line: 2*i + 2}})
				fmt.Fprintf(&source, "fn f%d() Int: 1\n", i)
			}
			m := &syntax.Module{File: "scale.ms", Source: source.String(), Declarations: decls}
			result := compiler.Result{Program: &checker.Program{Modules: []*syntax.Module{m}}}
			b.ReportAllocs()
			b.ResetTimer()
			for i := 0; i < b.N; i++ {
				for _, decl := range decls {
					_ = declarationDocumentation(result, decl)
				}
			}
		})
	}
}
