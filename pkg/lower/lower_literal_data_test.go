package lower

import (
	"bytes"
	"fmt"
	"github.com/manuscript-lang/manuscript/pkg/checker"
	"go/ast"
	"go/format"
	"go/token"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func TestLiteralDataCheckedScalarEligibility(t *testing.T) {
	for _, tc := range []struct {
		typ, item, extra, constructor string
		eligible, zero                bool
	}{
		{"Int", "7", "", "NewIntList", true, false},
		{"Int", "-9223372036854775808", "", "NewIntList", true, false},
		{"Int", "+7", "", "NewIntList", true, false},
		{"Float", "1.25", "", "NewFloatList", true, false},
		{"Float", "-1.25", "", "NewFloatList", true, false},
		{"Float", "-0.0", "", "NewFloatList", true, true},
		{"Float", "-1e-400", "", "NewFloatList", true, true},
		{"Bool", "true", "", "NewBoolList", true, false},
		{"String", `"λ\\n"`, "", "NewStringList", true, false},
		{"Int", "input", "", "", false, false},
		{"Int", "-(-9223372036854775808)", "", "", false, false},
		{"String", `"${input}"`, "", "", false, false},
		{"List[Int]", "[1]", "", "", false, false},
		{"Box", "Box(7)", "type Box:\n    value: Int\n", "", false, false},
	} {
		t.Run(tc.typ+tc.item, func(t *testing.T) {
			source := tc.extra + "fn values(input: Int) -> List[" + tc.typ + "]:\n    return [" + strings.TrimSuffix(strings.Repeat(tc.item+", ", 1100), ", ") + "]\n"
			result := compileSource("literal-data.ms", source)
			if !result.Success() {
				t.Fatal(result.Diagnostics)
			}
			if strings.Contains(result.Source, "literalData1") != tc.eligible || strings.Contains(result.Source, "rt.Unary(\"-\", float64(0))") != tc.zero {
				t.Fatalf("wrong eligibility or zero handling for %s", tc.item)
			}
			if tc.eligible && !strings.Contains(result.Source, "rt."+tc.constructor+"(\"@std/List[") {
				t.Fatal("lost checked constructor identity")
			}
			debug, err := Go(result.Program, "literal-data.ms", Options{DebugLiterals: true})
			if err != nil || strings.Contains(debug, "literalData1") {
				t.Fatal("optimized lowering reached explicit Debug", err)
			}
		})
	}
}

func TestLiteralDataBoundariesAndAST(t *testing.T) {
	for _, n := range []int{1024, 1025, 16000, 100000} {
		t.Run(fmt.Sprint(n), func(t *testing.T) {
			source := "fn values() -> List[Int]:\n    return [" + strings.TrimSuffix(strings.Repeat("7, ", n), ", ") + "]\n"
			result := analyzeSource("literal-data.ms", source)
			if !result.Success() {
				t.Fatal(result.Diagnostics)
			}
			g := &generator{program: result.Program}
			var literal *syntax.Expression
			for expression := range result.Program.Expressions {
				if expression.Kind == syntax.KindList && len(expression.Elements) == n {
					literal = expression
					break
				}
			}
			if literal == nil {
				t.Fatal("missing checked literal")
			}
			value := g.literalListData(literal, result.Program.Expressions[literal].Type)
			if (value != nil) != (n > largeListThreshold) {
				t.Fatal("wrong data threshold")
			}
			if value != nil {
				var printed bytes.Buffer
				if err := format.Node(&printed, token.NewFileSet(), value); err != nil {
					t.Fatal(err)
				}
				if printed.String() != `rt.NewIntList("@std/List[Int]", literalData1[:])` {
					t.Fatal(printed.String())
				}
				if len(g.literalData) != 1 {
					t.Fatal("unexpected initializer or expression helpers")
				}
				printed.Reset()
				if err := format.Node(&printed, token.NewFileSet(), g.literalData[0]); err != nil {
					t.Fatal(err)
				}
				if !strings.HasPrefix(printed.String(), fmt.Sprintf("var literalData1 = [%d]int64{", n)) {
					t.Fatal("data is not a typed static array")
				}
			}
		})
	}
}

func TestIneligibleLiteralDataDoesNotLowerOperands(t *testing.T) {
	source := "fn values() -> List[Int]:\n    return [" + strings.Repeat("7, ", 1099) + `match some(1):
        some(value): value
        none: 2
    ]
`
	result := compileSource("literal-data.ms", source)
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	if strings.Contains(result.Source, "literalData") {
		t.Fatal("effectful literal was globalized")
	}
}

func TestLargeLiteralInitializationIsOrderedAndBounded(t *testing.T) {
	const elements = 16000
	source := "fn tick(value: Int) -> Int: value\nfn values() -> List[Int]:\n    return [" + strings.TrimSuffix(strings.Repeat("tick(7), ", elements), ", ") + "]\n"
	result := analyzeSource("large.ms", source)
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	g := &generator{program: result.Program, captures: map[*checker.Binding]string{}}
	file := g.file("large.ms", Options{})
	next, helpers := 0, 0
	ast.Inspect(file, func(node ast.Node) bool {
		function, ok := node.(*ast.FuncLit)
		if !ok || len(function.Body.List) == 0 {
			return true
		}
		first, ok := function.Body.List[0].(*ast.ExprStmt)
		if !ok {
			return true
		}
		call, ok := first.X.(*ast.CallExpr)
		if !ok {
			return true
		}
		name, ok := call.Fun.(*ast.SelectorExpr)
		if !ok || name.Sel.Name != "InitListInt" {
			return true
		}
		if len(function.Body.List) > 64 {
			t.Fatal("oversized initialization helper")
		}
		helpers++
		for _, statement := range function.Body.List {
			statement := statement.(*ast.ExprStmt)
			call := statement.X.(*ast.CallExpr)
			index := call.Args[1].(*ast.BasicLit)
			if index.Value != fmt.Sprint(next) {
				t.Fatalf("element order: %s after %d", index.Value, next-1)
			}
			next++
		}
		return true
	})
	if next != elements || helpers != (elements+63)/64 {
		t.Fatal("missing initialization", next, helpers)
	}
	printed, err := g.printGo(file)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(printed, "rt.NewSizedIntList(") || !strings.Contains(printed, "rt.FinishListInitialization(") || strings.Contains(printed, "literalData") {
		t.Fatal("invalid sized construction")
	}
}
