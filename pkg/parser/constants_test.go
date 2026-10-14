package parser_test

import (
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/parser"
)

func TestModuleConstantsParseAsConstantFunctions(t *testing.T) {
	module, err := parser.Parse("constants.ms", "export let LIMIT = 10\nlet NAMES: List[String] = [\"a\"]\n")
	if err != nil {
		t.Fatal(err)
	}
	if len(module.Declarations) != 2 {
		t.Fatalf("got %d declarations", len(module.Declarations))
	}
	limit, names := module.Declarations[0], module.Declarations[1]
	if !limit.Constant || !limit.Export || limit.Name != "LIMIT" || limit.Result.Name != "" || len(limit.Params) != 0 {
		t.Fatalf("unexpected constant %+v", limit)
	}
	if !names.Constant || names.Result.Name != "List" {
		t.Fatalf("annotation not kept: %+v", names.Result)
	}
}
