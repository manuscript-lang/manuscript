package golower

import (
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/checker"
)

// TestRepresentation pins the reference/value classes documented in
// documentation/contributing/go-lowering-representation.md.
func TestRepresentation(t *testing.T) {
	for _, c := range []struct {
		name      string
		typ       *checker.Type
		reference bool
	}{
		{"Int", &checker.Type{Kind: "primitive", ID: "Int"}, false},
		{"List", &checker.Type{Kind: "native", ID: "@std/List"}, true},
		{"Map", &checker.Type{Kind: "native", ID: "@std/Map"}, true},
		{"Set", &checker.Type{Kind: "native", ID: "@std/Set"}, true},
		{"record", &checker.Type{Kind: "record", ID: "module#P"}, true},
		{"handle", &checker.Type{Kind: "native", ID: "@std/File"}, true},
		{"alternative", &checker.Type{Kind: "alternative", ID: "module#A"}, false},
		{"contract", &checker.Type{Kind: "contract", ID: "module#C"}, false},
		{"function", &checker.Type{Kind: "function"}, false},
		{"Optional", &checker.Type{Kind: "alternative", ID: "@std/Optional"}, false},
		{"Result", &checker.Type{Kind: "alternative", ID: "@std/Result"}, false},
	} {
		if got := isReference(c.typ); got != c.reference {
			t.Errorf("%s: isReference = %v, want %v", c.name, got, c.reference)
		}
	}
}
