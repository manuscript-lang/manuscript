package lower

import (
	"bytes"
	"go/format"
	"go/token"
	"strconv"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	rt "github.com/manuscript-lang/manuscript/pkg/runtime"
)

func TestGeneratedTypeKeys(t *testing.T) {
	integer := &checker.Type{Kind: "primitive", ID: "Int"}
	variable := &checker.Type{Kind: "variable", ID: "T"}
	list := func(arg *checker.Type) *checker.Type {
		return &checker.Type{Kind: "record", ID: "@std/List", Args: []*checker.Type{arg}}
	}
	function := func(param, result *checker.Type) *checker.Type {
		return &checker.Type{Kind: "function", ID: "fn", Params: []checker.Param{{Name: "value", Type: param}}, Result: result}
	}
	for _, test := range []struct {
		name    string
		typ     *checker.Type
		dynamic bool
	}{
		{"nil", nil, false},
		{"primitive", integer, false},
		{"nested concrete", list(list(integer)), false},
		{"variable", variable, true},
		{"nested variable", list(list(variable)), true},
		{"concrete function", function(list(integer), integer), false},
		{"function parameter", function(list(variable), integer), true},
		{"function result", function(integer, list(variable)), true},
		{"recursive definition", &checker.Type{Kind: "record", ID: "Node", Def: &checker.Definition{Variables: []*checker.Type{variable}}}, false},
	} {
		t.Run(test.name, func(t *testing.T) {
			key := checker.TypeKey(test.typ)
			want := strconv.Quote(key)
			if test.dynamic {
				want = "rt.ResolveType(" + want + ", typeArgs)"
			}
			var output bytes.Buffer
			if err := format.Node(&output, token.NewFileSet(), (&generator{}).key(test.typ)); err != nil {
				t.Fatal(err)
			}
			if got := output.String(); got != want {
				t.Fatalf("key = %s, want %s", got, want)
			}
			if !test.dynamic && rt.ResolveType(key, map[string]string{"T": "String"}) != key {
				t.Fatal("constant differs from runtime resolution")
			}
		})
	}
}

var benchmarkTypeKey string

// Compare the old emitted expression with the constant now emitted for a
// concrete nested collection. Keep the result observable in both cases.
func BenchmarkConcreteTypeKey(b *testing.B) {
	const key = "@std/List[@std/List[Int]]"
	substitutions := map[string]string{}
	b.Run("resolved", func(b *testing.B) {
		b.ReportAllocs()
		for b.Loop() {
			benchmarkTypeKey = rt.ResolveType(key, substitutions)
		}
	})
	b.Run("constant", func(b *testing.B) {
		b.ReportAllocs()
		for b.Loop() {
			benchmarkTypeKey = key
		}
	})
}

func BenchmarkGenerateConcreteCollections(b *testing.B) {
	result := analyzeSource("benchmark.ms", `fn nested(value: Int) -> List[List[Int]]:
    return [[value], [value]]
export fn main() -> Int:
    let values = nested(42)
    return 0
`)
	if !result.Success() {
		b.Fatal(result.Diagnostics)
	}
	b.ReportAllocs()
	for b.Loop() {
		if _, err := Go(result.Program, "benchmark.ms", Options{Entry: true}); err != nil {
			b.Fatal(err)
		}
	}
}
