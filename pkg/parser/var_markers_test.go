package parser_test

import (
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/parser"
)

func TestVarMarkersParse(t *testing.T) {
	source := "type Box:\n    items: List[Int]\n\nimpl Box:\n    var fn push(var items: List[Int], value: Int) Unit:\n        self.items.append(value)\n\nfn run(var xs: List[Int]) Unit:\n    xs.append(1)\n\nfn main() Unit:\n    var xs: List[Int] = []\n    run(var xs)\n    run(xs: var xs)\n"
	module, err := parser.Parse("var.ms", source)
	if err != nil {
		t.Fatal(err)
	}
	method := module.Declarations[1].Methods[0]
	if !method.Mutating || !method.Params[0].Var || method.Params[1].Var {
		t.Fatalf("method markers: %+v", method)
	}
	if !module.Declarations[2].Params[0].Var {
		t.Fatal("parameter marker lost")
	}
	body := module.Declarations[3].Body
	for _, i := range []int{1, 2} {
		if args := body[i].Value.Args; len(args) != 1 || !args[0].Var {
			t.Fatalf("statement %d arguments: %+v", i, args)
		}
	}
}

func TestVarParameterRejectedInFunctionTypes(t *testing.T) {
	if _, err := parser.Parse("var.ms", "fn run(callback: fn(var x: Int) Unit) Unit:\n    return\n"); err == nil {
		t.Fatal("function types cannot declare var parameters")
	}
}
