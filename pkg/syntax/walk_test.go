package syntax_test

import (
	"reflect"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/parser"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func TestVisitorFollowsExecutableSyntaxOnce(t *testing.T) {
	const source = `fn choose(value: Int) Int:
    return value
fn collect(fallback: Int = choose(1)) String:
    let callbacks = [
        fn(value: Int = choose(2)) Int:
            if value > 0:
                return choose(3)
            else:
                return choose(4)
    ]
    let text = "{choose(5)}"
    match fallback:
        _:
            return "{choose(6)}"
interface Read:
    fn read(value: Int) Int
type Box:
    value: Int = choose(7)
impl Read for Box:
    fn read(value: Int = choose(8)) Int:
        return choose(9)
`
	m, err := parser.Parse("walk.ms", source)
	if err != nil {
		t.Fatal(err)
	}
	var calls []string
	seen := map[*syntax.Expression]bool{}
	var stack []*syntax.Expression
	v := syntax.Visitor{Expression: func(e *syntax.Expression) {
		if seen[e] {
			t.Fatal("visited an expression twice", e.Pos)
		}
		seen[e] = true
		stack = append(stack, e)
		if e.Kind == "call" && e.Left.Text == "choose" {
			calls = append(calls, e.Args[0].Value.Text)
		}
	}, LeaveExpression: func(e *syntax.Expression) {
		if len(stack) == 0 || stack[len(stack)-1] != e {
			t.Fatal("leave callbacks do not balance nested expression traversal", e.Pos)
		}
		stack = stack[:len(stack)-1]
	}}
	for _, decl := range m.Declarations {
		v.Walk(decl)
	}
	if !reflect.DeepEqual(calls, []string{"1", "2", "3", "4", "5", "6", "7", "8", "9"}) {
		t.Fatal("lost or reordered default, closure, interpolation, arm, or method calls", calls)
	}
	if len(stack) != 0 {
		t.Fatal("missing leave callbacks", stack)
	}
}

func TestVisitorIncludesAssignmentTargetBeforeValue(t *testing.T) {
	const source = `fn update() Unit:
    owner().value = replacement()
`
	m, err := parser.Parse("assignment.ms", source)
	if err != nil {
		t.Fatal(err)
	}
	var calls []string
	v := syntax.Visitor{Expression: func(e *syntax.Expression) {
		if e.Kind == "call" {
			calls = append(calls, e.Left.Text)
		}
	}}
	for _, decl := range m.Declarations {
		v.Walk(decl)
	}
	if !reflect.DeepEqual(calls, []string{"owner", "replacement"}) {
		t.Fatalf("assignment evaluation order: %v", calls)
	}
}
