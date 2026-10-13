package compiler

import (
	"bytes"
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func TestLargeListLiteralRepresentation(t *testing.T) {
	for _, tc := range []struct {
		name, typ, element, declarations string
		count, tables                    int
	}{
		{"small", "Int", "1", "", largeListLiteral, 0},
		{"int", "Int", "-7", "", largeListLiteral + 1, 1},
		{"float", "Float", "-1.25", "", largeListLiteral + 1, 1},
		{"bool", "Bool", "true", "", largeListLiteral + 1, 1},
		{"string", "String", `"λ\\quote\"\n"`, "", largeListLiteral + 1, 1},
		{"negative zero", "Float", "-0.0", "", largeListLiteral + 1, 0},
		{"decimal", "Decimal", "1.2d", "import Decimal from \"@std/decimal.ms\"\n", largeListLiteral + 1, 0},
		{"record", "Box", "Box(1)", "type Box:\n    value: Int\n", largeListLiteral + 1, 0},
		{"nested list", "List[Int]", "[1]", "", largeListLiteral + 1, 0},
		{"local", "Int", "value", "", largeListLiteral + 1, 0},
	} {
		t.Run(tc.name, func(t *testing.T) {
			source := "import List from \"@std/collections.ms\"\n" + tc.declarations + "fn values(value: Int) -> List[" + tc.typ + "]:\n    return [" + strings.TrimSuffix(strings.Repeat(tc.element+", ", tc.count), ", ") + "]\n"
			result := CompileSource("literal.ms", source, Options{})
			if !result.Success() {
				t.Fatal(result.Diagnostics)
			}
			file, err := parser.ParseFile(token.NewFileSet(), "generated.go", result.Source, 0)
			if err != nil {
				t.Fatal(err)
			}
			tables, assignments := 0, 0
			ast.Inspect(file, func(node ast.Node) bool {
				if spec, ok := node.(*ast.ValueSpec); ok && strings.HasPrefix(spec.Names[0].Name, "literalData") {
					tables++
					ast.Inspect(spec, func(node ast.Node) bool {
						if expr, ok := node.(*ast.CallExpr); ok {
							name, ok := expr.Fun.(*ast.Ident)
							if !ok || name.Name != "int64" && name.Name != "float64" {
								t.Fatal("table contains a runtime operation")
							}
						}
						return true
					})
				}
				if fn, ok := node.(*ast.FuncLit); ok {
					writes := 0
					for _, statement := range fn.Body.List {
						if assignment, ok := statement.(*ast.AssignStmt); ok {
							if _, ok := assignment.Lhs[0].(*ast.IndexExpr); ok {
								writes++
							}
						}
					}
					if writes > listLiteralChunk {
						t.Fatalf("unbounded literal helper: %d assignments", writes)
					}
					assignments += writes
				}
				return true
			})
			if tables != tc.tables {
				t.Fatalf("data tables = %d, want %d", tables, tc.tables)
			}
			if tc.count > largeListLiteral && tc.tables == 0 && assignments != tc.count {
				t.Fatalf("element writes = %d, want %d", assignments, tc.count)
			}
		})
	}
}

// Frozen on main a6dcb33a4c3123a4dc7f9e805eaebcabcfa3a4f0, before this
// representation change. Never regenerate the independent executable oracle.
func TestLargeListLiteralAgainstBaseline(t *testing.T) {
	source, err := os.ReadFile("testdata/flat-literals/program.ms")
	if err != nil {
		t.Fatal(err)
	}
	baseline, err := os.ReadFile("testdata/flat-literals/baseline.go.txt")
	if err != nil {
		t.Fatal(err)
	}
	result := CompileSource("flat-baseline.ms", string(source), Options{Tests: true})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	if bytes.Equal(baseline, []byte(result.Source)) || !strings.Contains(result.Source, "literalData") {
		t.Fatal("fixture did not exercise the representation change")
	}
	if !reflect.DeepEqual(sourceDirectives(string(baseline)), sourceDirectives(result.Source)) {
		t.Fatal("source directive targets or order changed")
	}
	repeated := CompileSource("flat-baseline.ms", string(source), Options{Tests: true})
	if !repeated.Success() || repeated.Source != result.Source {
		t.Fatal("nondeterministic output")
	}
	for _, kind := range []BuildType{Release, Debug} {
		t.Run(string(kind), func(t *testing.T) {
			var outputs []string
			for _, generated := range []string{string(baseline), result.Source} {
				binary := filepath.Join(t.TempDir(), "program")
				if err := BuildWithType(generated, binary, kind); err != nil {
					t.Fatal(err)
				}
				output, err := exec.Command(binary).CombinedOutput()
				if err != nil {
					t.Fatalf("native fixture: %v\n%s", err, output)
				}
				outputs = append(outputs, string(output))
			}
			if outputs[0] != outputs[1] || !strings.Contains(outputs[1], "1 tests, 0 failed") {
				t.Fatalf("baseline behavior differs: %q", outputs)
			}
		})
	}
}
