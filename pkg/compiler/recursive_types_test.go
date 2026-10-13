package compiler

import (
	"strings"
	"testing"
)

func TestRecursiveTypesPreserveInitializationAndHashing(t *testing.T) {
	recursive := "type Node:\n    value: Int\n    next: Optional[Node]\n"
	for _, tt := range []struct{ name, source, want string }{
		{"self initialization", recursive + "fn f() -> Unit:\n    let node = Node(value: 1, next: node)\n", "unknown binding node"},
		{"missing required field", recursive + "fn f() -> Unit:\n    let node = Node(value: 1)\n", "missing argument next"},
		{"wrong recursive field", recursive + "fn f() -> Unit:\n    let node = Node(value: 1, next: \"wrong\")\n", "expected Optional[Node]"},
		{"direct hash", recursive + "fn f(node: Node) -> Int: return node.hash()\n", "unknown or ambiguous member hash"},
		{"map key", "import Map from \"@std/collections.ms\"\n" + recursive + "fn f(values: Map[Node, Int]) -> Unit: return\n", "does not satisfy Hashable"},
		{"set element", "import Set from \"@std/collections.ms\"\n" + recursive + "fn f(values: Set[Node]) -> Unit: return\n", "does not satisfy Hashable"},
		{"generic hash bound", recursive + "fn hash[T: Hashable](value: T) -> Int: return value.hash()\nfn f(node: Node) -> Int: return hash(node)\n", "does not satisfy Hashable"},
		{"generic callback expansion", "import List from \"@std/collections.ms\"\ntype Grow[T]:\n    next: fn() -> Grow[List[T]]\n", "recursive generic applications"},
		{"generic contract expansion", "import List from \"@std/collections.ms\"\ninterface Grow[T]:\n    fn next() -> Grow[List[T]]\n", "recursive generic applications"},
		{"expanding implemented interface parameter", `import List from "@std/collections.ms"
interface I[T]:
    fn f(x: I[List[T]]) -> Int

type Box[T]:
    v: T
impl I[T] for Box[T]:
    fn f(x: I[List[T]]) -> Int:
        return 1
export fn main() -> Int:
    let b = Box[Int](v: 1)
    let i = I[Int](value: b)
    return 0
`, "recursive generic applications"},
		{"nonexhaustive recursive match", "type Expr:\n    case Num(value: Int)\n    case Add(left: Expr, right: Expr)\nfn value(expr: Expr) -> Int:\n    match expr:\n        Num(value): return value\n", "non-exhaustive match"},
	} {
		t.Run(tt.name, func(t *testing.T) {
			result := CompileSource("recursive.ms", tt.source, Options{})
			for _, d := range result.Diagnostics {
				if strings.Contains(d.Message, tt.want) {
					return
				}
			}
			t.Fatalf("wanted %q, got %v", tt.want, result.Diagnostics)
		})
	}
	for _, source := range []string{
		recursive + "fn compare(left: Node, right: Node) -> Bool: return left == right\n",
		"type Pair:\n    left: Int\n    right: Int\nfn hash(pair: Pair) -> Int: return pair.hash()\n",
		"type Box[T]:\n    value: T\nfn hash(box: Box[Box[Int]]) -> Int: return box.hash()\n",
		"type Expr:\n    case Num(value: Int)\n    case Add(left: Expr, right: Expr)\nfn tree() -> Expr: return Expr.Add(left: Expr.Num(1), right: Expr.Num(2))\n",
	} {
		result := CompileSource("recursive.ms", source, Options{})
		if !result.Success() {
			t.Fatal(result.Diagnostics)
		}
	}
}
