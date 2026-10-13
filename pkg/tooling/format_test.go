package tooling_test

import (
	"encoding/json"
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"github.com/manuscript-lang/manuscript/pkg/lexer"
	"github.com/manuscript-lang/manuscript/pkg/parser"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
	"github.com/manuscript-lang/manuscript/pkg/tooling"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func TestFormatFixturesPreservesMeaningAndIsIdempotent(t *testing.T) {
	files, _ := filepath.Glob("../../tests/e2e/testdata/accept/*.ms")
	for _, filename := range files {
		t.Run(filepath.Base(filename), func(t *testing.T) {
			input, err := os.ReadFile(filename)
			if err != nil {
				t.Fatal(err)
			}
			formatted, err := tooling.Format(filename, string(input))
			if err != nil {
				t.Fatal(err)
			}
			assertFormatMeaning(t, filename, string(input), formatted)
			twice, err := tooling.Format(filename, formatted)
			if err != nil || formatted != twice {
				t.Fatal("formatter is not idempotent", err)
			}
			original := compiler.CompileSource("fixture.ms", string(input), compiler.Options{Tests: true})
			changed := compiler.CompileSource("fixture.ms", formatted, compiler.Options{Tests: true})
			if !original.Success() || !changed.Success() {
				t.Fatal(original.Diagnostics, changed.Diagnostics)
			}
		})
	}
}

func TestFormatImplicitReturnPreservesOperands(t *testing.T) {
	source := "fn sum(first_value: Int, second_value: Int, third_value: Int, fourth_value: Int) -> Int: first_value + second_value + third_value + fourth_value\n"
	formatted, err := tooling.Format("implicit.ms", source)
	if err != nil {
		t.Fatal(err)
	}
	assertFormatMeaning(t, "implicit.ms", source, formatted)
	twice, err := tooling.Format("implicit.ms", formatted)
	if err != nil || formatted != twice {
		t.Fatal("implicit return formatting is not idempotent", err)
	}
	if result := compiler.CompileSource("implicit.ms", formatted, compiler.Options{}); !result.Success() {
		t.Fatal(result.Diagnostics)
	}
}

// Grouping parentheses do not appear in the AST. Compare every other token's
// spelling and the complete syntax tree with source positions removed, so
// wrapping cannot change precedence, arguments, literals, or suite ownership.
func assertFormatMeaning(t *testing.T, filename, original, formatted string) {
	t.Helper()
	shape := func(source string) any {
		module, err := parser.Parse(filename, source)
		if err != nil {
			t.Fatal(err)
		}
		data, err := json.Marshal(module)
		if err != nil {
			t.Fatal(err)
		}
		var tree any
		if err := json.Unmarshal(data, &tree); err != nil {
			t.Fatal(err)
		}
		root := tree.(map[string]any)
		delete(root, "File")
		delete(root, "Source")
		var positions func(any)
		positions = func(value any) {
			switch node := value.(type) {
			case map[string]any:
				delete(node, "Pos")
				delete(node, "NamePos")
				for _, child := range node {
					positions(child)
				}
			case []any:
				for _, child := range node {
					positions(child)
				}
			}
		}
		positions(tree)
		return tree
	}
	if !reflect.DeepEqual(shape(original), shape(formatted)) {
		t.Fatalf("formatting changed the syntax tree:\n%s", formatted)
	}
	code := func(source string) []lexer.Token {
		tokens, err := lexer.Lex(filename, source)
		if err != nil {
			t.Fatal(err)
		}
		var result []lexer.Token
		for _, token := range tokens {
			switch token.Kind {
			case "(", ")", lexer.Newline, lexer.Indent, lexer.Dedent, lexer.EOF:
				continue
			}
			token.Pos = syntax.Position{}
			result = append(result, token)
		}
		return result
	}
	if !reflect.DeepEqual(code(original), code(formatted)) {
		t.Fatal("formatting changed token spellings")
	}
}
func TestFormatCommentsAndErrors(t *testing.T) {
	input := "# leading\r\nfn sum( left:Int,right:Int )->Int: # sum\r\n    return left+right # trailing\r\n"
	want := "# leading\nfn sum(left: Int, right: Int) -> Int:  # sum\n    return left + right  # trailing\n"
	formatted, err := tooling.Format("sum.ms", input)
	if err != nil || formatted != want {
		t.Fatalf("got %q, err %v", formatted, err)
	}
	formatted, err = tooling.Format("bad.ms", "fn bad():\n  return\n")
	if err == nil || formatted != "" {
		t.Fatal("invalid syntax produced output")
	}
}
func TestInspectionDeterminismAndOriginalSpans(t *testing.T) {
	source := "fn one() -> Int:\r\n    return 1\r\ntest \"calls\":\r\n    if one() != 1:\r\n        return\r\n"
	result := compiler.CompileSource("inspect.ms", source, compiler.Options{})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	first := tooling.Inspect(result.Program)
	second := tooling.Inspect(result.Program)
	if first.BuildID != second.BuildID || len(first.Calls) != 1 {
		t.Fatal("unstable inspection")
	}
	call := first.Calls[0]
	if !strings.HasPrefix(source[call.Span.Start:], "one()") || call.Span.End > len(source) {
		t.Fatal(call.Span)
	}
	diagram := tooling.Diagram(first)
	if !strings.Contains(diagram, "flowchart TD") || !strings.Contains(diagram, "inspect.ms::one") {
		t.Fatal(diagram)
	}
}

func TestInspectInterface(t *testing.T) {
	source := "export interface Read[T]:\n    fn get() -> T\n"
	result := compiler.CompileSource("interface.ms", source, compiler.Options{})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	inspection := tooling.Inspect(result.Program)
	if len(inspection.Entities) != 1 {
		t.Fatal(inspection.Entities)
	}
	entity := inspection.Entities[0]
	if entity.Kind != "interface" || entity.Name != "Read" || !entity.Exported || entity.Span.Start != 7 {
		t.Fatalf("incorrect interface entity: %+v", entity)
	}
}

func TestFormatGroupedImports(t *testing.T) {
	input := "import { List,Map, } from \"@std/collections.ms\" # collections\n"
	want := "import {List, Map,} from \"@std/collections.ms\"  # collections\n"
	formatted, err := tooling.Format("imports.ms", input)
	if err != nil || formatted != want {
		t.Fatalf("got %q, err %v", formatted, err)
	}
	twice, err := tooling.Format("imports.ms", formatted)
	if err != nil || twice != formatted {
		t.Fatal("formatting is not idempotent", err)
	}
}

func TestFormatMultilineFunctionParameters(t *testing.T) {
	input := "export fn render(\r\n    arguments:List[String], # arguments\r\n    output:WriteStream,\r\n)->Int:\r\n    let message=\"Arguments: {arguments.join(\",\")}\\n\"\r\n    match output.write(data:message.to_bytes()):\r\n        ok(_):\r\n            return 0\r\n        error(_):\r\n            return 1\r\n"
	want := "export fn render(\n    arguments: List[String],  # arguments\n    output: WriteStream,\n) -> Int:\n    let message = \"Arguments: {arguments.join(\",\")}\\n\"\n\n    match output.write(data: message.to_bytes()):\n        ok(_):\n            return 0\n        error(_):\n            return 1\n"
	formatted, err := tooling.Format("main.ms", input)
	if err != nil || formatted != want {
		t.Fatalf("got %q, err %v", formatted, err)
	}
	twice, err := tooling.Format("main.ms", formatted)
	if err != nil || twice != formatted {
		t.Fatal("formatting is not idempotent", err)
	}
}

func TestFormatInlineSuites(t *testing.T) {
	source := "fn double(x:Int)->Int:return x*2\nfn f(x:Int)->Int:\n    if x>0:return double(x)\n    else:return 0\n"
	formatted, err := tooling.Format("inline.ms", source)
	if err != nil {
		t.Fatal(err)
	}
	want := "fn double(x: Int) -> Int: return x * 2\n\nfn f(x: Int) -> Int:\n    if x > 0: return double(x)\n    else: return 0\n"
	if formatted != want {
		t.Fatalf("got %q, want %q", formatted, want)
	}
	again, err := tooling.Format("inline.ms", formatted)
	if err != nil || again != formatted {
		t.Fatalf("format is not stable: %q, %v", again, err)
	}
}

func TestFormatMapAndShorthand(t *testing.T) {
	source := "fn f() -> Unit:\n    let values={\"a\":1,\"b\":{1:2},}\n    consume(values,other: {})\n"
	formatted, err := tooling.Format("map.ms", source)
	if err != nil {
		t.Fatal(err)
	}
	again, err := tooling.Format("map.ms", formatted)
	if err != nil || again != formatted {
		t.Fatalf("not idempotent: %q %v", again, err)
	}
	if !strings.Contains(formatted, `{"a": 1, "b": {1: 2},}`) {
		t.Fatal(formatted)
	}
}
