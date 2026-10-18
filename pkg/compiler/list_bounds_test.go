package compiler_test

import (
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"strings"
	"testing"
)

func TestClosedIntListBoundsLowering(t *testing.T) {
	for _, tc := range []struct {
		name, prefix, body string
		checked            bool
	}{
		{"literal length", "let values = [1, 2, 3]", "while i < 1000:\n        sum += values.length()\n        i += 1", false},
		{"literal traversal", "let values = [1, 2, 3]", "for value in values:\n        sum += value", false},
		{"implicit default", "let values = [1, 2, 3]", "for value in values:\n        sum += values.get(value, 0)", false},
		{"explicit Optional default", "let values = [1, 2, 3]", "for value in values:\n        sum += values.get(value, some(9223372036854775807))", true},
		{"unknown Optional default", "let values = [1, 2, 3]", "for value in values:\n        sum += values.get(value, fallback)", true},
		{"overflowing default", "let values = [1, 2, 3]", "for value in values:\n        sum += values.get(value, 9223372036854775807)", true},
		{"alias", "let values = [1, 2, 3]\n    let alias = values", "while i < 1000:\n        sum += values.length()\n        i += 1", true},
		{"append result alias", "let values = [1, 2, 3]\n    let alias = values.append(4)", "while i < 1000:\n        sum += values.length()\n        i += 1", true},
		{"bound member", "let values = [1, 2, 3]\n    let read = values.get", "while i < 1000:\n        sum += values.length()\n        i += 1", true},
		{"capture", "let values = [1, 2, 3]\n    let read = fn() Int: values.length()", "while i < 1000:\n        sum += values.length()\n        i += 1", true},
		{"unsupported mutation", "let values = [1, 2, 3]\n    values.pop()", "while i < 1000:\n        sum += values.length()\n        i += 1", true},
		{"mutation during traversal", "let values = [1, 2, 3]", "for value in values:\n        sum += value\n        values.append(4)", true},
		{"intermediate overflow", "let values = [9223372036854775807, 1, -1]", "for value in values:\n        sum += value", true},
		{"self append", "let values = [1]\n    var fill = 0\n    while fill < 100:\n        values.append(values.get(-1) + 1)\n        fill += 1", "for value in values:\n        sum += value", true},
		{"peer append", "let values = [1]\n    let peer = [2]\n    var fill = 0\n    while fill < 100:\n        values.append(peer.get(-1))\n        peer.append(values.get(-1))\n        fill += 1", "for value in values:\n        sum += value", true},
		{"induction fill", "let values: List[Int] = []\n    var fill = 0\n    while fill < 100:\n        values.append(fill)\n        fill += 1", "for value in values:\n        sum += value", false},
		{"conditional fill", "let values: List[Int] = []\n    var fill = 0\n    while fill < 100:\n        if flag:\n            values.append(fill)\n        fill += 1", "while i < 1000:\n        sum += values.length()\n        i += 1", false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			source := "fn probe(flag: Bool, fallback: Optional[Int]) Int:\n    " + tc.prefix + "\n    var sum = 0\n    var i = 0\n    " + tc.body + "\n    return sum\n"
			r := compiler.CompileSource("lists.ms", source, compiler.Options{})
			if !r.Success() {
				t.Fatal(r.Diagnostics)
			}
			if got := strings.Contains(r.Source, "sum = rt.IntAdd("); got != tc.checked {
				t.Fatalf("checked=%v want %v:\n%s", got, tc.checked, r.Source)
			}
		})
	}
}

func TestClosedIntListExactLength(t *testing.T) {
	for _, conditional := range []bool{false, true} {
		appendBody := "values.append(i)"
		if conditional {
			appendBody = "if flag:\n            values.append(i)"
		}
		source := "fn probe(flag: Bool) Int:\n    let values: List[Int] = []\n    var i = 0\n    while i < 100:\n        " + appendBody + "\n        i += 1\n    return values.length()\n"
		r := compiler.CompileSource("lists.ms", source, compiler.Options{})
		if !r.Success() {
			t.Fatal(r.Diagnostics)
		}
		if got := strings.Contains(r.Source, "len(values.Items)"); got != conditional {
			t.Fatalf("conditional=%v retained len=%v:\n%s", conditional, got, r.Source)
		}
	}
}

func TestClosedIntListGenericAndLambdaIsolation(t *testing.T) {
	for _, source := range []string{
		`fn count[T](values: List[T]) Int: return values.length()
fn probe() Int:
    let values = [1, 2, 3]
    var sum = 0
    var i = 0
    while i < 1000:
        sum += count[Int](values)
        i += 1
    return sum
`,
		`fn probe(value: Int) Int:
    let values = [1, 2, 3]
    let callback = fn() Int:
        var sum = value
        for item in values:
            sum += item
        return sum
    return callback()
`,
	} {
		r := compiler.CompileSource("isolation.ms", source, compiler.Options{})
		if !r.Success() || !strings.Contains(r.Source, "sum = rt.IntAdd(") {
			t.Fatalf("lost fallback: %v\n%s", r.Diagnostics, r.Source)
		}
	}
	source := `fn probe() Int:
    let values = [1, 2, 3]
    var sum = 0
    for item in values:
        sum += item
    return sum + values.length()
`
	r := compiler.CompileSource("debug.ms", source, compiler.Options{BuildType: compiler.Debug})
	if !r.Success() || !strings.Contains(r.Source, "sum = rt.IntAdd(") || !strings.Contains(r.Source, "len(values.Items)") {
		t.Fatalf("Debug lost source operations: %v\n%s", r.Diagnostics, r.Source)
	}
}
