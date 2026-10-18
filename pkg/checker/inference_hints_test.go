package checker_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/parser"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func TestKnownStandardTypeImportHint(t *testing.T) {
	m, err := parser.Parse("import-hint.ms", "fn boxed(value: SetBuilder[Int]) Unit: return\n")
	if err != nil {
		t.Fatal(err)
	}
	p := checker.Check([]*syntax.Module{m}, nil)
	if len(p.Diagnostics) != 1 || !strings.Contains(p.Diagnostics[0].Message, `add: import SetBuilder from "@std/collections.ms"`) {
		t.Fatalf("expected canonical SetBuilder import hint, got %v", p.Diagnostics)
	}
}

func TestReturnOnlyTypeParameterContext(t *testing.T) {
	for _, body := range []string{
		`return fail("empty")`,
		`let result: Result[Int, String] = fail("empty")
    return result`,
	} {
		source := `fn fail[T](message: String) Result[T, String]: error(message)
fn first() Result[Int, String]:
    ` + body + "\n"
		m, err := parser.Parse("inference-hint.ms", source)
		if err != nil {
			t.Fatal(err)
		}
		p := checker.Check([]*syntax.Module{m}, nil)
		if len(p.Diagnostics) != 0 {
			t.Fatalf("expected result context to infer T, got %v", p.Diagnostics)
		}
	}
}

func TestUnknownTypeDoesNotCascadeIntoInference(t *testing.T) {
	source := `fn collect[T, U](items: List[T], step: fn(value: T) Result[List[U], MissingError]) Result[List[U], MissingError]:
    return step(items.at(0).get())
fn first() Unit:
    let result = collect(items: [1, 2], step: fn(value: Int) Result[List[Int], MissingError]: ok([value]))
    let unrelated: Int = "wrong"
`
	m, err := parser.Parse("unknown-inference.ms", source)
	if err != nil {
		t.Fatal(err)
	}
	p := checker.Check([]*syntax.Module{m}, nil)
	resolution, independent := 0, 0
	for _, d := range p.Diagnostics {
		switch {
		case d.Phase == "resolution" && strings.Contains(d.Message, "unknown type MissingError"):
			resolution++
		case strings.Contains(d.Message, "expected Int, found String"):
			independent++
		default:
			t.Errorf("unexpected cascade: %v", d)
		}
	}
	if resolution != 3 || independent != 1 {
		t.Fatalf("lost independent diagnostics: %v", p.Diagnostics)
	}
}

func TestReturnOnlyTypeParameterExplicitSpecialization(t *testing.T) {
	m, err := parser.Parse("explicit-inference.ms", `fn fail[T](message: String) Result[T, String]: error(message)
fn first() Result[Int, String]: fail[Int]("empty")
`)
	if err != nil {
		t.Fatal(err)
	}
	p := checker.Check([]*syntax.Module{m}, nil)
	if len(p.Diagnostics) != 0 {
		t.Fatal(p.Diagnostics)
	}
}

func TestMissingTypeArgumentHintRetainsKnownArguments(t *testing.T) {
	m, err := parser.Parse("partial-inference.ms", `fn convert[T, U](value: T) Optional[U]: none
fn first() Unit:
    let value = convert(1)
`)
	if err != nil {
		t.Fatal(err)
	}
	p := checker.Check([]*syntax.Module{m}, nil)
	if len(p.Diagnostics) != 1 || !strings.Contains(p.Diagnostics[0].Message, "cannot infer type argument U for convert; write convert[Int, U](...)") {
		t.Fatalf("expected missing U and known Int, got %v", p.Diagnostics)
	}
}

func TestUnknownTypeKeepsIndependentInferenceError(t *testing.T) {
	m, err := parser.Parse("independent-inference.ms", `fn broken(value: Missing) Unit: return
fn empty[T]() Optional[T]: none
fn first() Unit:
    let value = empty()
`)
	if err != nil {
		t.Fatal(err)
	}
	p := checker.Check([]*syntax.Module{m}, nil)
	if len(p.Diagnostics) != 2 || !strings.Contains(p.Diagnostics[0].Message, "unknown type Missing") || !strings.Contains(p.Diagnostics[1].Message, "cannot infer type argument T for empty") {
		t.Fatalf("expected both independent errors, got %v", p.Diagnostics)
	}
}
