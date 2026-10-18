package parser

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func pipeValue(t *testing.T, expression string) *syntax.Expression {
	t.Helper()
	source := "fn f() Int:\n    let v = " + expression + "\n    return 0\n"
	module, err := Parse("pipe.ms", source)
	if err != nil {
		t.Fatalf("%s: %v", expression, err)
	}
	return module.Declarations[0].Body[0].Value
}

func TestPipeDesugarsToCalls(t *testing.T) {
	call := pipeValue(t, "x | f")
	if call.Kind != syntax.KindCall || call.Left.Text != "f" || len(call.Args) != 1 || call.Args[0].Value.Text != "x" {
		t.Fatalf("x | f: %+v", call)
	}
	call = pipeValue(t, "x | m.f(a: 1, 2)")
	if call.Left.Kind != syntax.KindMember || len(call.Args) != 3 || call.Args[0].Value.Text != "x" || call.Args[1].Name != "a" {
		t.Fatalf("x | m.f(a: 1, 2): %+v", call)
	}
	call = pipeValue(t, "x | .m(1)")
	if call.Kind != syntax.KindCall || call.Left.Kind != syntax.KindMember || call.Left.Left.Text != "x" || len(call.Args) != 1 {
		t.Fatalf("x | .m(1): %+v", call)
	}
	try := pipeValue(t, "x | try f")
	if try.Kind != syntax.KindUnary || try.Text != "try" || try.Right.Kind != syntax.KindCall {
		t.Fatalf("x | try f: %+v", try)
	}
	bare := pipeValue(t, "x | .m() | try")
	if bare.Kind != syntax.KindUnary || bare.Text != "try" || bare.Right.Kind != syntax.KindCall {
		t.Fatalf("bare try: %+v", bare)
	}
}

func TestPipeIsLeftAssociativeAndLowestPrecedence(t *testing.T) {
	outer := pipeValue(t, "a + b | f | g")
	if outer.Left.Text != "g" || outer.Args[0].Value.Left.Text != "f" || outer.Args[0].Value.Args[0].Value.Kind != syntax.KindBinary {
		t.Fatalf("a + b | f | g: %+v", outer)
	}
	head := pipeValue(t, "try read() | f")
	if head.Kind != syntax.KindCall || head.Args[0].Value.Kind != syntax.KindUnary {
		t.Fatalf("a leading try binds only the head: %+v", head)
	}
}

func TestPipeContinuationLines(t *testing.T) {
	source := "fn f() Int:\n    let v = x\n        | f # first\n\n        # explain\n        | g(a: 1)\n        .size()\n    return 0\n"
	module, err := Parse("pipe.ms", source)
	if err != nil {
		t.Fatal(err)
	}
	if got := module.Declarations[0].Body[0].Value; got.Kind != syntax.KindCall || got.Left.Text != "size" {
		t.Fatalf("continuation chain: %+v", got)
	}
	if _, issues := ParsePartial("pipe.ms", source); len(issues) != 0 {
		t.Fatal(issues)
	}
}

func TestPipeRejections(t *testing.T) {
	for source, want := range map[string]string{
		"x | 1":              "pipe step",
		"x | f(a)(b)":        "end of statement",
		"x | (f)":            "pipe step",
		"x || y":             "'||' is not an operator",
		"x | f + 1":          "lowest precedence",
		"x | f == y":         "lowest precedence",
		"x | fn(n: Int): n":  "pipe step",
		"x | make().run":     "",
		"x | f\n        | g": "",
		"x | f\n    | g":     "indented four spaces",
	} {
		module := "fn f() Int:\n    let v = " + source + "\n    return 0\n"
		_, err := Parse("pipe.ms", module)
		if want == "" {
			if err != nil {
				t.Errorf("%q: %v", source, err)
			}
			continue
		}
		if err == nil || !strings.Contains(err.Error(), want) {
			t.Errorf("%q: error %v, want %q", source, err, want)
		}
	}
}

func TestPipeNextLineDotAppliesToStepResult(t *testing.T) {
	parse := func(body string) *syntax.Expression {
		t.Helper()
		module, err := Parse("pipe.ms", "fn f() Int:\n    let v = x\n"+body+"    return 0\n")
		if err != nil {
			t.Fatalf("%q: %v", body, err)
		}
		return module.Declarations[0].Body[0].Value
	}
	named := parse("        | Box\n        .size()\n")
	if named.Kind != syntax.KindCall || named.Left.Kind != syntax.KindMember || named.Left.Text != "size" ||
		named.Left.Left.Kind != syntax.KindCall || named.Left.Left.Left.Text != "Box" {
		t.Fatalf("a next-line .member extended the step's name path: %+v", named)
	}
	bare := parse("        | try\n        .size()\n")
	if bare.Kind != syntax.KindCall || bare.Left.Kind != syntax.KindMember || bare.Left.Left.Kind != syntax.KindUnary || bare.Left.Left.Text != "try" {
		t.Fatalf("a next-line .member after a bare try must apply to the unwrapped value: %+v", bare)
	}
	same := parse("        | try .size()\n")
	if same.Kind != syntax.KindUnary || same.Text != "try" || same.Right.Kind != syntax.KindCall {
		t.Fatalf("a same-line .member after try stays inside the try: %+v", same)
	}
}

func TestPipeDiagnosticsExplainRejectedShapes(t *testing.T) {
	for _, test := range []struct{ expression, want string }{
		{"x | f[Int]", "cannot take type arguments"},
		{"x |\n", "start the next line with '|'"},
	} {
		source := "fn f() Int:\n    let v = " + test.expression + "\n    return 0\n"
		_, err := Parse("pipe.ms", source)
		if err == nil || !strings.Contains(err.Error(), test.want) {
			t.Errorf("%q: %v, want %q", test.expression, err, test.want)
		}
	}
}
