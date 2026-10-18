package checker_test

import (
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/parser"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func TestExpectedResultKeepsConcreteSpecialization(t *testing.T) {
	source := `type Failure:
    detail: String
impl Error for Failure:
    fn message() String: self.detail
fn fail_cause[T, E: Error](cause: E) Result[T, E]: error(cause)
fn first() Result[Int, Error]: fail_cause(Failure("empty"))
`
	m, err := parser.Parse("context-specialization.ms", source)
	if err != nil {
		t.Fatal(err)
	}
	p := checker.Check([]*syntax.Module{m}, nil)
	if len(p.Diagnostics) != 0 {
		t.Fatal(p.Diagnostics)
	}
	found := false
	for expression, info := range p.Expressions() {
		if expression.Kind != syntax.KindCall || info.Symbol == nil || info.Symbol.Name != "fail_cause" {
			continue
		}
		found = true
		if len(info.TypeArgs) != 2 || info.TypeArgs[0].String() != "Int" || info.TypeArgs[1].String() != "Failure" {
			t.Fatalf("lost concrete specialization: %v", info.TypeArgs)
		}
		if info.ErrorSource == nil || info.ErrorSource.String() != "Result[Int, Failure]" {
			t.Fatalf("lost Error-boundary source: %v", info.ErrorSource)
		}
	}
	if !found {
		t.Fatal("missing checked call")
	}
}

func TestExpectedFunctionResultErasesDefaultPermissions(t *testing.T) {
	source := `fn from_callback[T](factory: fn() T) T: factory()
fn first() Unit:
    let callback: fn(value: Int) Int = from_callback(fn(): fn(value: Int = 4): value)
`
	m, err := parser.Parse("context-defaults.ms", source)
	if err != nil {
		t.Fatal(err)
	}
	p := checker.Check([]*syntax.Module{m}, nil)
	if len(p.Diagnostics) != 0 {
		t.Fatal(p.Diagnostics)
	}
	found := false
	for expression, info := range p.Expressions() {
		if expression.Kind != syntax.KindCall || info.Symbol == nil || info.Symbol.Name != "from_callback" {
			continue
		}
		found = true
		if len(info.TypeArgs) != 1 || info.TypeArgs[0].Kind != "function" || len(info.TypeArgs[0].Defaults) != 0 {
			t.Fatalf("inferred function retained default permissions: %#v", info.TypeArgs)
		}
	}
	if !found {
		t.Fatal("missing checked call")
	}
}

func TestExpectedGenericResultUnknownContextDoesNotCascade(t *testing.T) {
	source := `import {TextError} from "@std/errors.ms"
fn fail[T](message: String) Result[T, TextError]: error(TextError(message))
fn first() Result[Int, Missing]: fail("empty")
`
	m, err := parser.Parse("unknown-context.ms", source)
	if err != nil {
		t.Fatal(err)
	}
	p := checker.Check([]*syntax.Module{m}, nil)
	if len(p.Diagnostics) != 1 || p.Diagnostics[0].Phase != "resolution" {
		t.Fatalf("expected only unresolved result type, got %v", p.Diagnostics)
	}
}

func TestGenericResultParameterWidensDomainError(t *testing.T) {
	source := `type Failure:
    code: Int
impl Error for Failure:
    fn message() String: "failure"
fn failing() Result[Int, Failure]: error(Failure(code: 1))
fn count[T](r: Result[T, Error]) Int: 1
fn use() Int: count(r: failing())
`
	m, err := parser.Parse("widen-inference.ms", source)
	if err != nil {
		t.Fatal(err)
	}
	if p := checker.Check([]*syntax.Module{m}, nil); len(p.Diagnostics) != 0 {
		t.Fatal(p.Diagnostics)
	}
}
