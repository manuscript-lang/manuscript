package lsp

import (
	"strings"
	"testing"
)

func TestMatchExpressionAndIndexReferences(t *testing.T) {
	source := `fn read(values: List[Int], index: Int) Int:
    let result = match values.take(index).first():
        some(number):
            let doubled = number * 2
            doubled
        none: 0
    return result
`
	d := document{"file:///tmp/match.ms", source, 1}
	docs := map[string]document{d.URI: d}
	result := analyze(d, docs)
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	for _, item := range []struct {
		text, name string
		count      int
	}{
		{"index)", "index", 2}, {"number *", "number", 2}, {"doubled\n", "doubled", 2},
	} {
		pos := Position(source, strings.Index(source, item.text))
		refs := references(result, d, pos, true)
		if len(refs) != item.count {
			t.Fatalf("%s references: %v", item.name, refs)
		}
		if _, err := rename(result, d, pos, "renamed", docs); err != nil {
			t.Fatal(err)
		}
	}
}
