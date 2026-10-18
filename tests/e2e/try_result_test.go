package e2e_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestTryResultPreservesPayloads(t *testing.T) {
	result := compiler.CompileSource("try-result.ms", `import panic from "@std/faults.ms"

type Failure:
    detail: String

impl Error for Failure:
    fn message() String: self.detail

fn relay[T, E](result: Result[T, E], visits: List[Int]) Result[T, E]:
    let value = try result
    visits.append(1)
    return ok(value)

fn text(result: Result[Int, String]) Result[String, String]:
    let value = try result
    return ok(value.to_string())

fn widened(result: Result[Int, Failure]) Result[Int, Error]:
    let value = try result
    return ok(value)

test "try returns zero-valued errors and skips success effects":
    let visits: List[Int] = []
    if relay(Result[Int, String].error(""), visits).is_ok():
        return panic("empty error became success")
    if relay(Result[String, Bool].error(false), visits).is_ok():
        return panic("false error became success")
    if visits.length() != 0:
        return panic("success path ran after failure")
    if relay(Result[Int, String].ok(0), visits).get() != 0 or visits.length() != 1:
        return panic("zero success was lost")

test "try can change the success type":
    if text(Result[Int, String].error("failed")).err() != "failed":
        return panic("changed return type lost error")
    if text(Result[Int, String].ok(42)).get() != "42":
        return panic("changed return type lost success")

test "try retains aliases and error views":
    let visits: List[Int] = []
    let original = Failure("before")
    let exact = relay(Result[Int, Failure].error(original), visits)
    let abstract = widened(Result[Int, Failure].error(original))
    original.detail = "after"
    if exact.err().detail != "after" or abstract.err().message() != "after":
        return panic("propagation copied an error receiver")
    if widened(Result[Int, Failure].ok(7)).get() != 7:
        return panic("widening changed success")
`, compiler.Options{Tests: true})
	output, err := execute(t, result)
	if err != nil || !strings.Contains(string(output), "3 tests, 0 failed") {
		t.Fatalf("try result payloads changed: %v\n%s", err, output)
	}
}
