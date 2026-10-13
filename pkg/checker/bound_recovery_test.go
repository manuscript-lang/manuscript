package checker

import (
	"context"
	"os"
	"os/exec"
	"runtime/debug"
	"strings"
	"testing"
	"time"

	"github.com/manuscript-lang/manuscript/pkg/parser"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func TestInvalidBoundsTerminate(t *testing.T) {
	if os.Getenv("MANUSCRIPT_BOUND_RECOVERY_CHILD") == "1" {
		debug.SetMaxStack(1 << 20)
		checkInvalidBounds(t)
		checkCyclicBoundMembers(t)
		return
	}
	executable, err := os.Executable()
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	command := exec.CommandContext(ctx, executable, "-test.run=^TestInvalidBoundsTerminate$")
	command.Env = append(os.Environ(), "MANUSCRIPT_BOUND_RECOVERY_CHILD=1")
	if output, err := command.CombinedOutput(); err != nil {
		t.Fatalf("bound recovery failed: %v (%v)\n%s", err, ctx.Err(), output)
	}
}

func checkInvalidBounds(t *testing.T) {
	t.Helper()
	for _, source := range []string{
		"type Box[Error: Error]:\n    cause: Error\nimpl Error for Box[Error]:\n    fn message() -> String: self.cause.message()\n",
		"fn recursive[T: T](value: T) -> Unit: return\n",
		"fn mutual[T: U, U: T](value: T) -> Unit: return\n",
		"fn primitive[T: Int](value: T) -> Unit: return\n",
		"type Data:\n    value: Int\nfn record[T: Data](value: T) -> Unit: return\n",
		"fn unknown[T: Missing](value: T) -> Unit: return\n",
	} {
		module, err := parser.Parse("bounds.ms", source)
		if err != nil {
			t.Fatal(err)
		}
		program := Check([]*syntax.Module{module}, nil)
		if len(program.Diagnostics) == 0 {
			t.Fatalf("invalid bound accepted: %s", source)
		}
		want := "a bound must be an interface"
		if strings.Contains(source, "Missing") {
			want = "unknown type Missing"
			if len(program.Diagnostics) != 1 {
				t.Fatal(program.Diagnostics)
			}
		}
		if !strings.Contains(program.Diagnostics[0].Message, want) {
			t.Fatal(program.Diagnostics)
		}
		for _, symbol := range program.Symbols[module.File] {
			for _, variable := range symbol.Variables {
				for _, bound := range variable.Bounds {
					if bound.Kind != "contract" {
						t.Fatalf("retained invalid bound: %#v", bound)
					}
				}
			}
		}
	}
}

func checkCyclicBoundMembers(t *testing.T) {
	t.Helper()
	first := &Type{Kind: "variable", Name: "T", ID: "T"}
	second := &Type{Kind: "variable", Name: "U", ID: "U"}
	contract := &Type{Kind: "contract", Name: "Show", ID: "Show", Def: &Definition{Operations: []Param{{Name: "show", Type: &Type{Kind: "function", ID: "fn", Result: primitive("String")}}}}}
	first.Bounds = []*Type{first, second, contract}
	second.Bounds = []*Type{first}
	program := &Program{}
	c := &checker{Program: program}
	names := c.memberNames(first)
	if len(names) != 1 || names[0] != "show" {
		t.Fatal(names)
	}
	found := false
	for _, member := range Members(program, first) {
		found = found || member.Name == "show"
	}
	if !found {
		t.Fatal("lost valid operation while recovering cyclic bounds")
	}
}
