package checker_test

import (
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/parser"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func TestIndependentArgumentsRetainFinalConversions(t *testing.T) {
	source := `type Cause[T]:
    detail: T
impl Error for Cause[T]:
    fn message() String: self.detail.to_string()
fn identity[T](value: T) T: value
fn consume[T](value: T, cause: Error, optional: Optional[T]) Unit: return
fn first() Unit: consume(value: 1, cause: identity(Cause(2)), optional: identity(3))
`
	module, err := parser.Parse("argument-conversions.ms", source)
	if err != nil {
		t.Fatal(err)
	}
	program := checker.Check([]*syntax.Module{module}, nil)
	if len(program.Diagnostics) != 0 {
		t.Fatal(program.Diagnostics)
	}
	errors, optionals := 0, 0
	for expression, info := range program.Expressions() {
		if expression.Kind != syntax.KindCall || info.Symbol == nil || info.Symbol.Name != "identity" {
			continue
		}
		if info.ErrorSource != nil {
			errors++
			if info.ErrorSource.String() != "Cause[Int]" || !info.ScopedError || info.Type.String() != "Error" || len(info.TypeArgs) != 1 || info.TypeArgs[0].String() != "Cause[Int]" {
				t.Fatalf("lost scoped Error conversion: %#v", info)
			}
		}
		if info.OptionalArgument != nil {
			optionals++
			if info.OptionalArgument.String() != "Optional[Int]" || info.Type.String() != "Int" {
				t.Fatalf("lost source type or Optional wrapping: %#v", info)
			}
		}
	}
	if errors != 1 || optionals != 1 {
		t.Fatalf("expected one conversion each, got errors=%d optionals=%d", errors, optionals)
	}
}
