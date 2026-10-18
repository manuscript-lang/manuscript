package lower

import (
	"strings"
	"testing"
)

func TestListItemsCacheOnlyLoopsThatCannotReplaceItems(t *testing.T) {
	cases := []struct {
		name   string
		body   string
		cached bool
	}{
		{"indexed reads and writes", "    var i = 0\n    while i < 4:\n        values.set(i, values.get(i) + 1)\n        i += 1\n", true},
		{"direct append", "    var i = 0\n    while i < 4:\n        values.append(i)\n        i += 1\n", false},
		{"opaque call", "    var i = 0\n    while i < 4:\n        grow(values)\n        total += values.get(i)\n        i += 1\n", false},
		{"rebound list", "    var i = 0\n    while i < 4:\n        total += values.get(i)\n        values = other\n        i += 1\n", false},
		{"closure", "    var i = 0\n    while i < 4:\n        let read = fn() Int:\n            return values.get(0)\n        total += read()\n        i += 1\n", false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			source := "fn grow(values: List[Int]) Unit:\n    values.append(0)\n\nfn work(other: List[Int]) Int:\n    var values = [1, 2, 3, 4]\n    var total = 0\n" + c.body + "    return total\n"
			if c.name != "rebound list" {
				source = strings.Replace(source, "var values", "let values", 1)
			}
			got, err := Go(checkedLoweringProgram(t, source), "benchmark.ms", Options{})
			if err != nil {
				t.Fatal(err)
			}
			if cached := strings.Contains(got, "ItemsOf("); cached != c.cached {
				t.Fatalf("cached = %v, want %v:\n%s", cached, c.cached, got)
			}
		})
	}
}

func TestListItemsCacheKeepsDebugAndLocalsOrdinary(t *testing.T) {
	source := "fn work() Int:\n    let values = [1, 2]\n    var i = 0\n    var total = 0\n    while i < 2:\n        total += values.get(i)\n        i += 1\n    return total\n"
	got, err := Go(checkedLoweringProgram(t, source), "benchmark.ms", Options{PreserveBindings: true})
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(got, "ItemsOf(") {
		t.Fatalf("Debug lowering cached list items:\n%s", got)
	}
}
