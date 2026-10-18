package syntax_test

import (
	"reflect"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/parser"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

const nodesSource = `fn choose(value: Int) -> Int:
    return value
fn run(fallback: Int = choose(1), hook: fn(x: Int) -> Int) -> Int:
    let box: Array[Int] = [choose(3)]
    match fallback:
        Color.Red:
            return choose(5)
        _:
            return choose(6)
type Box:
    value: Int = choose(7)
interface Read:
    fn read(value: Int) -> Int
impl Read for Box:
    fn read(value: Int = choose(8)) -> Int:
        return choose(9)
`

func parseNodes(t *testing.T) *syntax.Module {
	t.Helper()
	m, err := parser.Parse("nodes.ms", nodesSource)
	if err != nil {
		t.Fatal(err)
	}
	return m
}

// Nodes reaches calls in defaults, fields, arms, and methods in source order,
// and also the arm path, which is a member expression.
func TestNodesVisitsEveryExpressionInSourceOrder(t *testing.T) {
	var calls []string
	members := 0
	syntax.Nodes{Expression: func(e *syntax.Expression) {
		if e.Kind == "member" {
			members++
		}
		if e.Kind == "call" && e.Left.Text == "choose" {
			calls = append(calls, e.Args[0].Value.Text)
		}
	}}.Module(parseNodes(t))
	want := []string{"1", "3", "5", "6", "7", "8", "9"}
	if !reflect.DeepEqual(calls, want) {
		t.Fatalf("call order = %v, want %v", calls, want)
	}
	if members != 1 {
		t.Fatalf("arm path member expressions = %d, want 1", members)
	}
}

// Nodes covers what Visitor leaves out: types, patterns, and arms. A parent is
// visited before its children.
func TestNodesCoversTypesPatternsAndArms(t *testing.T) {
	var types, names []string
	var patterns, arms, statements int
	syntax.Nodes{
		Type:        func(ty *syntax.Type) { types = append(types, ty.Name) },
		Pattern:     func(*syntax.Pattern) { patterns++ },
		Arm:         func(*syntax.Arm) { arms++ },
		Statement:   func(*syntax.Statement) { statements++ },
		Declaration: func(d *syntax.Declaration) { names = append(names, d.Name) },
	}.Module(parseNodes(t))
	if arms != 2 {
		t.Fatalf("arms = %d, want 2", arms)
	}
	if patterns == 0 || statements == 0 {
		t.Fatalf("patterns = %d, statements = %d", patterns, statements)
	}
	listAt, intAt := -1, -1
	for i, name := range types {
		if name == "Array" && listAt < 0 {
			listAt = i
		}
		if name == "Int" && listAt >= 0 && intAt < 0 {
			intAt = i
		}
	}
	if listAt < 0 || intAt < listAt {
		t.Fatalf("type %v: Array must precede its argument Int", types)
	}
	for _, want := range []string{"choose", "run", "Box", "read"} {
		found := false
		for _, got := range names {
			found = found || got == want
		}
		if !found {
			t.Fatalf("declaration %q not visited in %v", want, names)
		}
	}
}

// Visitor deliberately skips arm paths; pin the
// difference so a merge cannot change what Visitor callers see.
func TestVisitorSkipsArmPaths(t *testing.T) {
	var calls []string
	members := 0
	v := syntax.Visitor{Expression: func(e *syntax.Expression) {
		if e.Kind == "member" {
			members++
		}
		if e.Kind == "call" && e.Left.Text == "choose" {
			calls = append(calls, e.Args[0].Value.Text)
		}
	}}
	for _, d := range parseNodes(t).Declarations {
		v.Walk(d)
	}
	want := []string{"1", "3", "5", "6", "7", "8", "9"}
	if !reflect.DeepEqual(calls, want) {
		t.Fatalf("visitor calls = %v, want %v", calls, want)
	}
	if members != 0 {
		t.Fatalf("visitor reached %d arm path expressions", members)
	}
}
