package lsp

import (
	"strings"
	"testing"
)

func TestIfLetBindingReferencesAndRename(t *testing.T) {
	source := `fn read(values: List[Int]) -> Int:
    if let first = values.first:
        return first + 1
    return 0
`
	d := document{"file:///tmp/if_let.ms", source, 1}
	docs := map[string]document{d.URI: d}
	result := analyze(d, docs)
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	pos := Position(source, strings.Index(source, "first +"))
	if refs := references(result, d, pos, true); len(refs) != 2 {
		t.Fatalf("first references: %v", refs)
	}
	if _, err := rename(result, d, pos, "head", docs); err != nil {
		t.Fatal(err)
	}
}
