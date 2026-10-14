package lower

import (
	"go/ast"
	"reflect"
	"strings"
	"testing"
)

// Keep the exact issue #277 reproduction, including its nested constructor.
const interfaceViewRepro = `interface Read:
    fn read() -> Int
type Reader:
    operation: fn() -> Int
impl Read for Reader:
    fn read() -> Int:
        return self.operation()
export fn main() -> Int:
    let view = Read(Reader(fn() -> Int: 1))
    return view.read()
`

func TestInterfaceViewLowersReceiverOnce(t *testing.T) {
	for name, source := range map[string]string{
		"nested constructor": interfaceViewRepro,
		"separate binding": strings.Replace(interfaceViewRepro,
			"let view = Read(Reader(fn() -> Int: 1))",
			"let reader = Reader(fn() -> Int: 1)\n    let view = Read(reader)", 1),
		"nested capture": strings.Replace(interfaceViewRepro,
			"let view = Read(Reader(fn() -> Int: 1))",
			"let value = 1\n    let view = Read(Reader(fn() -> Int:\n        let nested = fn() -> Int: value\n        return nested()\n    ))", 1),
		"match receiver": strings.Replace(interfaceViewRepro,
			"Read(Reader(fn() -> Int: 1))",
			"Read(match some(1):\n        some(value): Reader(fn() -> Int: value)\n        none: Reader(fn() -> Int: 2)\n    )", 1),
	} {
		t.Run(name, func(t *testing.T) {
			checked := analyzeSource("views.ms", source)
			if !checked.Success() {
				t.Fatal(checked.Diagnostics)
			}
			g := newGenerator(checked.Program)
			file := g.file("views.ms", Options{})
			seen := map[string]int{}
			ast.Inspect(file, func(node ast.Node) bool {
				if label, ok := node.(*ast.LabeledStmt); ok {
					if _, sourceMarker := g.sourceLines[label.Label.Name]; sourceMarker {
						seen[label.Label.Name]++
					}
				}
				return true
			})
			for marker, pos := range g.sourceLines {
				if seen[marker] != 1 {
					t.Errorf("receiver lowering abandoned or duplicated %s (%s): %d occurrences", marker, pos, seen[marker])
				}
			}
			printed, err := g.printGo(file)
			if err != nil {
				t.Fatal(err)
			}
			if len(sourceDirectives(printed)) != len(g.sourceLines) {
				t.Fatal("lost source directives")
			}
			if name == "nested constructor" {
				want := []string{"//line views.ms:9", "//line views.ms:9", "//line manuscript.generated.go:1", "//line views.ms:10", "//line manuscript.generated.go:1", "//line views.ms:7", "//line manuscript.generated.go:1"}
				if !reflect.DeepEqual(sourceDirectives(printed), want) {
					t.Fatalf("source directive order/targets changed: %q", sourceDirectives(printed))
				}
			}
		})
	}
}
