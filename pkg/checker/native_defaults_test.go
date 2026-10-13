package checker

import (
	"fmt"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/parser"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func TestNativeDefaultsAreCheckedInParameterScope(t *testing.T) {
	ensureStandard()
	for _, item := range []struct{ source, want string }{
		{"fn f(first: Int, second: Int = first + 1) -> Int:\n", ""},
		{"fn f(value: Int = true) -> Int:\n", "expected Int, found Bool"},
		{"fn f(first: Int = second, second: Int = 1) -> Int:\n", "unknown binding second"},
		{"fn f(value: Int = value) -> Int:\n", "unknown binding value"},
		{"fn f(value: Bool = none) -> Bool:\n", "none default requires Optional"},
		{"fn f[T](value: T, copy: T = value) -> T:\n", "native generic expression defaults are not supported"},
		{"fn f[T](value: Optional[T] = none) -> Optional[T]:\n", ""},
	} {
		m, err := parser.Parse("@std/default-test.ms", item.source)
		if err != nil {
			t.Fatal(err)
		}
		c := &checker{standardDeclarations: true, Program: newProgram(nil), module: m, names: map[string]*Symbol{}, scope: newScope(nil), captures: map[int]map[*Binding]bool{}}
		for _, name := range []string{"Int", "Bool", "Unit"} {
			c.names[name] = &Symbol{Kind: syntax.KindType, Type: primitive(name)}
		}
		c.addStandardPrelude()
		d := m.Declarations[0]
		variables := c.typeVariables(d.TypeParams)
		typ := c.signature(d.Params, d.Result)
		c.checkNativeDefaults(d, d.Params, typ, variables)
		got := fmt.Sprint(c.Diagnostics)
		if item.want == "" && len(c.Diagnostics) != 0 || item.want != "" && !strings.Contains(got, item.want) {
			t.Errorf("%s: want %q, got %s", item.source, item.want, got)
		}
	}
}
