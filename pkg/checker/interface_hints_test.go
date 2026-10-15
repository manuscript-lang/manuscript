package checker_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/parser"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func TestInterfaceAndReceiverHints(t *testing.T) {
	const declarations = "interface Shape:\n    fn area() -> Int\ntype Sq:\n    s: Int\n"
	const implementation = "impl Shape for Sq:\n    fn area() -> Int: self.s * self.s\n"
	for _, tt := range []struct {
		name, source string
		want         []string
	}{
		{"view in return", declarations + implementation + "fn shape() -> Shape: Sq(2)\n", []string{"expected Shape, found Sq", "Sq implements Shape", "Shape(value: ...)"}},
		{"view in list", "" + declarations + implementation + "fn shapes() -> List[Shape]: [Sq(2)]\n", []string{"expected Shape, found Sq", "Shape(value: ...)"}},
		{"view in call", declarations + implementation + "fn area(shape: Shape) -> Int: shape.area()\nfn run() -> Int: area(Sq(2))\n", []string{"expected Shape, found Sq", "Shape(value: ...)"}},
		{"generic view", "interface Read[T]:\n    fn get() -> T\ntype Box[T]:\n    item: T\nimpl Read[T] for Box[T]:\n    fn get() -> T: self.item\nfn read() -> Read[Int]: Box(1)\n", []string{"Box[Int] implements Read[Int]", "Read[Int](value: ...)"}},
		{"missing implementation", declarations + "fn shape() -> Shape: Sq(2)\n", []string{"expected Shape, found Sq", "no applicable", "impl Shape for Sq"}},
		{"this receiver", "type E:\n    text: String\nimpl Error for E:\n    fn message() -> String: this.text\n", []string{"unknown binding this", "self"}},
		{"Error member value", "fn error_method() -> Unit:\n    let method = Error.message\n", []string{"Error is an interface", "impl Error for"}},
		{"Error type member", "fn error_value() -> Error: Error.message(\"bad input\")\n", []string{"Error is an interface", "impl Error for"}},
	} {
		t.Run(tt.name, func(t *testing.T) {
			m, err := parser.Parse("interface-hints.ms", tt.source)
			if err != nil {
				t.Fatal(err)
			}
			p := checker.Check([]*syntax.Module{m}, nil)
			if len(p.Diagnostics) != 1 {
				t.Fatalf("want one diagnostic, got %v", p.Diagnostics)
			}
			for _, want := range tt.want {
				if !strings.Contains(p.Diagnostics[0].Message, want) {
					t.Errorf("%q lacks %q", p.Diagnostics[0].Message, want)
				}
			}
		})
	}
}

func TestInterfaceHintCorrectionsAndReceiverScope(t *testing.T) {
	const declarations = "interface Shape:\n    fn area() -> Int\ntype Sq:\n    s: Int\nimpl Shape for Sq:\n    fn area() -> Int: self.s * self.s\n"
	for _, source := range []string{
		declarations + "fn shape() -> Shape: Shape(value: Sq(2))\n",
		declarations + "fn shape() -> Shape: Shape(Sq(2))\n",
		"type E:\n    text: String\nimpl Error for E:\n    fn message() -> String: self.text\nfn error_value() -> Error: E(\"bad input\")\n",
		"fn identity(this: Int) -> Int: this\n",
	} {
		m, err := parser.Parse("corrected.ms", source)
		if err != nil {
			t.Fatal(err)
		}
		if p := checker.Check([]*syntax.Module{m}, nil); len(p.Diagnostics) != 0 {
			t.Fatalf("corrected source rejected: %v", p.Diagnostics)
		}
	}
	for _, source := range []string{"fn f() -> Int: this\n"} {
		m, err := parser.Parse("receiver-scope.ms", source)
		if err != nil {
			t.Fatal(err)
		}
		p := checker.Check([]*syntax.Module{m}, nil)
		if len(p.Diagnostics) != 1 || strings.Contains(p.Diagnostics[0].Message, "receiver in an impl") {
			t.Fatalf("incorrect receiver hint: %v", p.Diagnostics)
		}
	}
}

func TestInterfaceViewHintUsesVisibleImplementations(t *testing.T) {
	data, err := parser.Parse("data.ms", "export type Sq:\n    s: Int\n")
	if err != nil {
		t.Fatal(err)
	}
	extension, err := parser.Parse("extension.ms", "import Sq from \"data.ms\"\nexport interface Shape:\n    fn area() -> Int\nimpl Shape for Sq:\n    fn area() -> Int: self.s * self.s\n")
	if err != nil {
		t.Fatal(err)
	}
	consumer, err := parser.Parse("consumer.ms", "import Sq from \"data.ms\"\nimport Shape from \"extension.ms\"\nfn shape() -> Shape: Sq(2)\n")
	if err != nil {
		t.Fatal(err)
	}
	imports := map[*syntax.Import]string{extension.Imports[0]: "data.ms", consumer.Imports[0]: "data.ms", consumer.Imports[1]: "extension.ms"}
	p := checker.Check([]*syntax.Module{data, extension, consumer}, imports)
	if len(p.Diagnostics) != 1 || !strings.Contains(p.Diagnostics[0].Message, "no applicable 'impl Shape for Sq' is visible") {
		t.Fatalf("hidden implementation hint: %v", p.Diagnostics)
	}
}

func TestInterfaceHintDoesNotRecommendInvalidImplementationReceivers(t *testing.T) {
	for _, source := range []string{
		"interface Shape:\n    fn area() -> Int\nfn f() -> Shape: 1\n",
		"interface A:\n    fn a() -> Int\ninterface B:\n    fn b() -> Int\nfn f(value: A) -> B: value\n",
		"interface Shape:\n    fn area() -> Int\nfn f[T](value: T) -> Shape: value\n",
		"interface Shape:\n    fn area() -> Int\nfn f(value: fn() -> Int) -> Shape: value\n",
	} {
		m, err := parser.Parse("view-hint.ms", source)
		if err != nil {
			t.Fatal(err)
		}
		p := checker.Check([]*syntax.Module{m}, nil)
		if len(p.Diagnostics) != 1 || strings.Contains(p.Diagnostics[0].Message, "declare an implementation") || !strings.Contains(p.Diagnostics[0].Message, "use a concrete value implementing") {
			t.Fatalf("invalid implementation hint: %v", p.Diagnostics)
		}
	}
}
