package lower

import (
	"go/ast"
	"go/parser"
	"go/token"
	"regexp"
	"strconv"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/checker"
)

func TestPrimitiveEqualityEligibility(t *testing.T) {
	for _, tc := range []struct {
		name, declarations, typ string
		direct                  bool
	}{
		{"int", "", "Int", true},
		{"float", "", "Float", true},
		{"bool", "", "Bool", true},
		{"string", "", "String", true},
		{"decimal", "import Decimal from \"@std/decimal.ms\"\n", "Decimal", false},
		{"unit", "", "Unit", false},
		{"generic", "", "T", false},
		{"nominal", "type Integer:\n    value: Bool\n", "Integer", false},
		{"recursive", "type Node:\n    next: Optional[Node]\n", "Node", false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			variables := ""
			if tc.typ == "T" {
				variables = "[T: Equal]"
			}
			r := compileSource("scalar.ms", tc.declarations+"fn equal"+variables+"(left: "+tc.typ+", right: "+tc.typ+") -> Bool: left == right\nfn unequal"+variables+"(left: "+tc.typ+", right: "+tc.typ+") -> Bool: left != right\n")
			if !r.Success() {
				t.Fatal(r.Diagnostics)
			}
			if got := strings.Contains(r.Source, "rt.Equality("); got == tc.direct {
				t.Fatalf("selected equality fallback = %v, direct = %v\n%s", got, tc.direct, r.Source)
			}
			// Scalar parameters are typed variables, so the comparison needs no assertion.
			goType := primitiveEqualityType(r.Program.ParameterBindings(r.Program.Symbol("scalar.ms", "equal").Decl)[0].Type)
			if tc.direct && (!regexp.MustCompile(`local\d+_left `+goType+`, `).MatchString(r.Source) || !strings.Contains(r.Source, " != ")) {
				t.Fatal("missing typed direct equality", r.Source)
			}
		})
	}
	// Eligibility follows canonical identity and kind, never a display spelling.
	for _, typ := range []*checker.Type{{ID: "Int", Kind: "variable"}, {ID: "Int", Kind: "contract"}, {ID: "Int", Kind: "primitive", Def: &checker.Definition{}}, {ID: "Int", Kind: "primitive", Args: []*checker.Type{{ID: "Bool"}}}, {ID: "module:Int", Name: "Int", Kind: "primitive"}} {
		if primitiveEqualityType(typ) != "" {
			t.Fatalf("accepted nonbuiltin type: %#v", typ)
		}
	}
}

func TestPrimitiveEqualityCannotBeOverridden(t *testing.T) {
	for _, typ := range []string{"Int", "Float", "Bool", "String"} {
		r := compileSource("override.ms", "impl Equal for "+typ+":\n    fn equals(other: Equal) -> Bool: true\n")
		if r.Success() {
			t.Fatal("accepted primitive override", typ)
		}
	}
}

// Count cleanup setup owned by a source callable, excluding nested source
// functions but including the generated closures used by match expressions.
// A callable is a direct function declaration registered with RegisterSource
// or a function literal passed to Named or NamedMethod; each carries its name.
func callableCleanupCounts(t *testing.T, source string) map[string]int {
	t.Helper()
	f, err := parser.ParseFile(token.NewFileSet(), "generated.go", source, 0)
	if err != nil {
		t.Fatal(err)
	}
	unquote := func(e ast.Expr) string {
		text, err := strconv.Unquote(e.(*ast.BasicLit).Value)
		if err != nil {
			t.Fatal(err)
		}
		return text
	}
	counts := map[string]int{}
	measure := func(name string, body *ast.BlockStmt) {
		count := 0
		ast.Inspect(body, func(node ast.Node) bool {
			if c, ok := node.(*ast.CallExpr); ok {
				if s, ok := c.Fun.(*ast.SelectorExpr); ok {
					if s.Sel.Name == "NewSourceFunction" || s.Sel.Name == "NewCompiledSourceFunction" || s.Sel.Name == "NamedFunc" || s.Sel.Name == "SourceDirect" {
						return false
					}
					if s.Sel.Name == "NewCleanupStack" {
						count++
					}
				}
			}
			return true
		})
		counts[name] = count
	}
	names := map[string]string{}
	ast.Inspect(f, func(n ast.Node) bool {
		if c, ok := n.(*ast.CallExpr); ok {
			if s, ok := c.Fun.(*ast.SelectorExpr); ok && s.Sel.Name == "RegisterSource" {
				names[c.Args[0].(*ast.Ident).Name] = unquote(c.Args[1])
			}
		}
		return true
	})
	ast.Inspect(f, func(n ast.Node) bool {
		switch n := n.(type) {
		case *ast.FuncDecl:
			if name, ok := names[n.Name.Name]; ok {
				measure(name, n.Body)
			}
		case *ast.CallExpr:
			if s, ok := n.Fun.(*ast.SelectorExpr); ok && (s.Sel.Name == "Named" || s.Sel.Name == "NamedMethod" || s.Sel.Name == "NamedFunc") {
				measure(unquote(n.Args[0]), n.Args[1].(*ast.FuncLit).Body)
			}
		}
		return true
	})
	return counts
}

func TestCallableCleanupOwnership(t *testing.T) {
	source := `import Closeable from "@std/cleanup.ms"
type Resource:
    value: Int
impl Closeable for Resource:
    fn close() -> Unit: return
fn empty() -> Unit: return
fn conditional(flag: Bool) -> Unit:
    if flag:
        with resource = Resource(1): return
fn nested() -> Unit:
    let callback = fn() -> Unit:
        with resource = Resource(1): return
    callback()
fn matched() -> Int:
    return match some(1):
        some(value):
            with resource = Resource(value):
                return value
            0
        none: 0
fn defaulted(value: Int = match some(1):
    some(number):
        with resource = Resource(number):
            let used = unit
        number
    none: 0
) -> Int: value
fn looped() -> Unit:
    while true:
        with resource = Resource(1): break
`
	r := compileSource("cleanup.ms", source)
	if !r.Success() {
		t.Fatal(r.Diagnostics)
	}
	counts := callableCleanupCounts(t, r.Source)
	for name, want := range map[string]int{"empty": 0, "conditional": 1, "nested": 0, "<anonymous>": 1, "matched": 1, "defaulted": 1, "looped": 1, "Resource.close": 0} {
		if got, ok := counts[name]; !ok || got != want {
			t.Fatalf("%s cleanup count = %d (present %v), want %d\n%s", name, got, ok, want, r.Source)
		}
	}
	if strings.Contains(r.Source, "TraceSource") || strings.Contains(r.Source, "rt.Leave(") {
		t.Fatal("source functions defer frame bookkeeping again")
	}
}
