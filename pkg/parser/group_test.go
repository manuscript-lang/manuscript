package parser

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func TestBindingGroupsParseAsIndividualBindings(t *testing.T) {
	source := `let (
    A = 1
    B: Int = A + 1
)

fn main() Unit:
    var (
        a = 10
        b = fn(x: Int) Int:
            return x + 1
    )
    let (
        c = 11
        d = "Hi"
    )
    a += 1
`
	module, err := Parse("group.ms", source)
	if err != nil {
		t.Fatal(err)
	}
	if len(module.Declarations) != 3 || !module.Declarations[0].Constant || module.Declarations[1].Name != "B" {
		t.Fatalf("declarations = %#v", module.Declarations)
	}
	if module.Declarations[0].Group.Line != 1 || module.Declarations[1].Group.Line != 1 || module.Declarations[2].Group.Line != 0 {
		t.Fatalf("group positions: %v %v %v", module.Declarations[0].Group, module.Declarations[1].Group, module.Declarations[2].Group)
	}
	body := module.Declarations[2].Body
	if len(body) != 5 {
		t.Fatalf("body = %d statements", len(body))
	}
	for i, want := range []struct {
		name    string
		mutable bool
	}{{"a", true}, {"b", true}, {"c", false}, {"d", false}} {
		s := body[i]
		if s.Kind != syntax.KindBind || s.Pattern.Name != want.name || s.Mutable != want.mutable || s.Group.Line == 0 {
			t.Fatalf("statement %d = %#v", i, s)
		}
	}
	if body[0].Group != body[1].Group || body[1].Group == body[2].Group || body[4].Kind != syntax.KindAssign {
		t.Fatalf("groups not tracked: %#v", body)
	}
}

func TestBindingGroupRejections(t *testing.T) {
	cases := map[string]string{
		"let (\n)\n":                   "cannot be empty",
		"let (\n    a = 1, b = 2\n)\n": "one 'name = value' per line",
		"let (\n  a = 1\n)\n":          "multiple of four",
		"let (\n        a = 1\n)\n":    "indented four spaces",
		"let (\n    a = 1\n    )\n":    "aligns with",
		"let (a, b) = pair\n":          "next line",
		"var (\n    a = 1\n)\n":        "top level holds only",
		"fn main() Unit:\n    if true: let (\n        a = 1\n    )\n": "own lines",
	}
	for source, want := range cases {
		_, err := Parse("bad.ms", source)
		if err == nil || !strings.Contains(err.Error(), want) {
			t.Errorf("%q: error %v, want %q", source, err, want)
		}
	}
}
