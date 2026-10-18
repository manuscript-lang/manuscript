package checker_test

import (
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/parser"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func TestOptionalArgumentPreservesSourceTypeAndAST(t *testing.T) {
	module, err := parser.Parse("optional.ms", "fn f(value: Optional[Int]) Int: return value.unwrap()\nfn call() Int: return f(4)\n")
	if err != nil {
		t.Fatal(err)
	}
	call := module.Declarations[1].Body[0].Value
	argument := call.Args[0].Value
	for range 2 {
		program := checker.Check([]*syntax.Module{module}, nil)
		if len(program.Diagnostics) != 0 {
			t.Fatal(program.Diagnostics)
		}
		info := program.Info(argument)
		if info.Type.ID != "Int" || info.OptionalArgument == nil || info.OptionalArgument.ID != "@std/Optional" || info.OptionalArgument.Args[0].ID != "Int" {
			t.Fatal("lost source type or optional argument conversion", info)
		}
		if call.Args[0].Name != "" || call.Args[0].Value != argument || argument.Kind != syntax.KindNumber || argument.Text != "4" {
			t.Fatal("checking rewrote the supplied source argument")
		}
	}
}

func TestMatchArmBindingsSurviveRepeatedFunctionLiteralChecks(t *testing.T) {
	source := "import TaskGroup from \"@std/tasks.ms\"\nfn get() Result[Int, String]: return ok(value: 1)\nfn note() Unit: return unit\nfn run() Unit:\n    with tasks = TaskGroup():\n        tasks.start(operation: fn() Int:\n            match get():\n                ok(n): note()\n                error(e): note()\n            return 0\n        )\n"
	module, err := parser.Parse("arms.ms", source)
	if err != nil {
		t.Fatal(err)
	}
	program := checker.Check([]*syntax.Module{module}, nil)
	if len(program.Diagnostics) != 0 {
		t.Fatal(program.Diagnostics)
	}
	arms := map[*syntax.Arm][]*checker.Binding{}
	for arm, bindings := range program.ArmBindings() {
		arms[arm] = bindings
	}
	if len(arms) != 2 {
		t.Fatalf("expected two checked arms, got %d", len(arms))
	}
	for arm, bindings := range arms {
		if len(bindings) != len(arm.Names) {
			t.Fatalf("arm %s recorded %d bindings for %d names", arm.Path.Text, len(bindings), len(arm.Names))
		}
	}
}
