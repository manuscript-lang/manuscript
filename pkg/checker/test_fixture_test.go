package checker_test

import (
	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/parser"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
	"strings"
	"testing"
)

func TestFileFixtureContracts(t *testing.T) {
	prefix := `import TestHooks from "@std/testing.ms"
type State:
    value: Int
`
	cases := []struct{ name, source, want string }{
		{"all omitted", prefix + `impl TestHooks for State:
fn make_fixture() -> State:
    return State(value: 1)
test "reads fixture":
    let value: Int = fixture.value
`, ""},
		{"partial", prefix + `impl TestHooks for State:
    fn before_each() -> Unit:
        self.value = self.value + 1
fn make_fixture() -> State:
    return State(value: 1)
test "closure captures fixture":
    let read = fn() -> Int: fixture.value
    let value: Int = read()
`, ""},
		{"wrong signature", prefix + `impl TestHooks for State:
    fn before_each(value: Int) -> Unit:
        return
fn make_fixture() -> State:
    return State(value: 1)
test "test":
    return
`, "signature does not match contract"},
		{"factory argument", prefix + `impl TestHooks for State:
fn make_fixture(value: Int) -> State:
    return State(value)
test "test":
    return
`, "zero-argument"},
		{"factory generic", prefix + `impl TestHooks for State:
fn make_fixture[T]() -> State:
    return State(1)
test "test":
    return
`, "nongeneric"},
		{"factory interface", prefix + `impl TestHooks for State:
fn make_fixture() -> TestHooks:
    return State(1)
test "test":
    return
`, "concrete type implementing"},
		{"no implementation", prefix + `fn make_fixture() -> State:
    return State(1)
test "test":
    return
`, "concrete type implementing"},
		{"outside test", prefix + `impl TestHooks for State:
fn make_fixture() -> State:
    return State(fixture.value)
test "test":
    return
`, "fixture is available only in tests"},
		{"no factory", prefix + `test "test":
    let value = fixture.value
`, "local make_fixture"},
		{"shadow interface", `interface TestHooks:
    fn after_all() -> Unit
type State:
    value: Int
impl TestHooks for State:
    fn after_all() -> Unit:
        return
fn make_fixture() -> State:
    return State(1)
test "test":
    return
`, "concrete type implementing"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			module, err := parser.Parse("fixture.ms", tc.source)
			if err != nil {
				t.Fatal(err)
			}
			program := checker.Check([]*syntax.Module{module}, nil)
			var messages []string
			for _, d := range program.Diagnostics {
				messages = append(messages, d.Message)
			}
			if tc.want == "" {
				if len(messages) > 0 {
					t.Fatal(messages)
				}
				if program.TestFixtures["fixture.ms"] == nil {
					t.Fatal("missing checked fixture")
				}
			} else if !strings.Contains(strings.Join(messages, "\n"), tc.want) {
				t.Fatalf("want %q, got %v", tc.want, messages)
			}
		})
	}
}
