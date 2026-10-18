package compiler_test

import (
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"strings"
	"testing"
)

func TestClosedLocalIntMapLowering(t *testing.T) {
	for _, tc := range []struct {
		name, prefix, body string
		local              bool
	}{
		{"direct calls", "let values = Map[Int, Int]()", "values.add(1, 2)\n    let found = values.get(1)\n    let present = values.contains(1)\n    let size = values.length()", true},
		{"mutable", "var values = Map[Int, Int]()", "values.add(1, 2)", false},
		{"alias", "let values = Map[Int, Int]()", "let alias = values\n    alias.add(1, 2)", false},
		{"returned add", "let values = Map[Int, Int]()", "let alias = values.add(1, 2)\n    let size = alias.length()", false},
		{"chained add", "let values = Map[Int, Int]()", "let size = values.add(1, 2).length()", false},
		{"argument", "let values = Map[Int, Int]()", "consume(values)", false},
		{"bound member", "let values = Map[Int, Int]()", "let add = values.add\n    let size = add(1, 2).length()", false},
		{"capture", "let values = Map[Int, Int]()", "let callback = fn() Int: values.length()\n    let size = callback()", false},
		{"default capture", "let values = Map[Int, Int]()", "let callback = fn(value: Int = values.length()) Int: value\n    let size = callback()", false},
		{"iteration", "let values = Map[Int, Int]()", "for entry in values:\n        let key = entry.key", false},
		{"format", "let values = Map[Int, Int]()", "let text = \"{values}\"", false},
		{"other operation", "let values = Map[Int, Int]()", "values.clear()", false},
		{"other value type", "let values = Map[Int, String]()", "values.add(1, \"two\")", false},
		{"other key type", "let values = Map[String, Int]()", "values.add(\"one\", 2)", false},
		{"grandchild capture", "let callback = fn() Int:\n        let values = Map[Int, Int]()\n        let child = fn() Int:\n            let grandchild = fn() Int: values.length()\n            return grandchild()\n        return child()", "let size = callback()", false},
		{"match operations", "let values = Map[Int, Int]()", "let size = match some(1):\n        some(n):\n            values.add(n, n)\n            values.get(n).get()\n        none: values.length()", true},
		{"match argument escape", "let values = Map[Int, Int]()", "consume(match some(1):\n        some(n): values\n        none: values\n    )", false},
		{"local in lambda", "let callback = fn() Int:\n        let values = Map[Int, Int]()\n        values.add(1, 2)\n        return values.get(1).get()", "let size = callback()", true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			source := "fn consume(values: Map[Int, Int]) Unit: unit\nfn probe() Int:\n    " + tc.prefix + "\n    " + tc.body + "\n    return 0\n"
			r := compiler.CompileSource("local.ms", source, compiler.Options{})
			if !r.Success() {
				t.Fatal(r.Diagnostics)
			}
			if got := strings.Contains(r.Source, "rt.NewLocalIntMap("); got != tc.local {
				t.Fatalf("local=%v want %v:\n%s", got, tc.local, r.Source)
			}
			if !tc.local && strings.Contains(r.Source, "rt.LocalIntMap_") {
				t.Fatal("partial local-map selection")
			}
		})
	}
}

func TestClosedLocalIntMapPreservesDebugStorage(t *testing.T) {
	r := compiler.CompileSource("local.ms", `fn probe() Int:
    let values = Map[Int, Int]()
    values.add(1, 2)
    return values.get(1).get()
`, compiler.Options{BuildType: compiler.Debug})
	if !r.Success() || strings.Contains(r.Source, "LocalIntMap") {
		t.Fatalf("Debug changed map storage: %v\n%s", r.Diagnostics, r.Source)
	}
}

func TestClosedLocalIntMapRejectsCustomKeyEvidence(t *testing.T) {
	r := compiler.CompileSource("local.ms", `type Key:
    value: Int
impl Equal for Key:
    fn equals(other: Equal) Bool: true
impl Hashable for Key:
    fn hash() Int: 0
fn probe() Int:
    let values = Map[Key, Int]()
    values.add(Key(1), 10)
    values.add(Key(2), 20)
    return values.length()
`, compiler.Options{})
	if !r.Success() || strings.Contains(r.Source, "LocalIntMap") {
		t.Fatalf("custom key evidence bypassed: %v\n%s", r.Diagnostics, r.Source)
	}
}

func TestClosedLocalIntMapIsolatesGenericInstances(t *testing.T) {
	r := compiler.CompileSource("local.ms", `fn lookup[T: Hashable](key: T, value: T) T:
    let values = Map[T, T]()
    values.add(key, value)
    return values.get(key).get()
fn probe() Int:
    let number = lookup[Int](1, 2)
    let text = lookup[String]("one", "two")
    return number
`, compiler.Options{})
	if !r.Success() || strings.Count(r.Source, "rt.NewLocalIntMap(") != 1 || !strings.Contains(r.Source, "rt.NewMapWith[string, string]") {
		t.Fatalf("instances shared local-map selection: %v\n%s", r.Diagnostics, r.Source)
	}
}
