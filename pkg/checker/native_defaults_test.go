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
		{"fn f[T](value: T, flag: Bool = true) -> T:\n", ""},
		{"fn f[T](value: T, flag: Int = 1 + 1) -> T:\n", "native generic expression defaults are not supported"},
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

func TestInheritedNativeDefaultsRejectDependenciesAndEffects(t *testing.T) {
	ensureStandard()
	for _, item := range []struct {
		source   string
		rejected bool
	}{
		{"fn f(first: Int, value: Int = first) -> Int:\n", true},
		{"fn f(value: Int = (fn() -> Int: 1)()) -> Int:\n", true},
		{"fn f(first: Int = 1, value: Optional[Int] = none) -> Int:\n", false},
		{"fn f(value: Bytes = \"\".to_bytes()) -> Bytes:\n", false},
	} {
		m, err := parser.Parse("@std/interface-default-test.ms", item.source)
		if err != nil {
			t.Fatal(err)
		}
		c := &checker{standardDeclarations: true, Program: newProgram(nil), module: m, names: map[string]*Symbol{}, scope: newScope(nil), captures: map[int]map[*Binding]bool{}}
		for _, name := range []string{"Int", "String"} {
			c.names[name] = &Symbol{Kind: syntax.KindType, Type: primitive(name)}
		}
		c.names["Bytes"] = standardSymbols["Bytes"]
		c.addStandardPrelude()
		d := m.Declarations[0]
		typ := c.signature(d.Params, d.Result)
		c.checkNativeDefaults(d, d.Params, typ, nil, true)
		if item.rejected != strings.Contains(fmt.Sprint(c.Diagnostics), "closed literals") || !item.rejected && len(c.Diagnostics) != 0 {
			t.Fatalf("%s: %v", item.source, c.Diagnostics)
		}
	}
}

func TestOpaqueNativeConstructorDefaultsStayBounded(t *testing.T) {
	m, err := parser.Parse("@std/opaque-default-test.ms", "type Resource:\n    size: Int = 1\n")
	if err != nil {
		t.Fatal(err)
	}
	c := &checker{standardDeclarations: true, Program: newProgram(nil)}
	d := m.Declarations[0]
	c.checkNativeDefaults(d, d.Fields, function([]Param{{"size", primitive("Int")}}, &Type{Kind: syntax.KindNative}), nil)
	if !strings.Contains(fmt.Sprint(c.Diagnostics), "delivery/disposal design") {
		t.Fatal(c.Diagnostics)
	}
}
