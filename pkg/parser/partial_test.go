package parser

import (
	"strings"
	"testing"
)

func TestPartialParserPreservesPositionsAndStrictFailure(t *testing.T) {
	source := "# prefix\r\nfn good(input: Int) -> Int:\r\n    return input\r\nfn broken(\r\nfn later() -> Int:\r\n    return 2\r\n"
	if _, err := Parse("source.ms", source); err == nil {
		t.Fatal("strict parser accepted incomplete source")
	}
	module, issues := ParsePartial("source.ms", source)
	if len(issues) == 0 || len(module.Declarations) != 2 {
		t.Fatal(module, issues)
	}
	later := module.Declarations[1]
	if later.Pos.Line != 5 || later.Pos.Offset != strings.Index(source, "fn later") || later.Body[0].Value.Pos.Offset != strings.Index(source, "2\r\n") {
		t.Fatal(later)
	}
}

func FuzzParsePartial(f *testing.F) {
	for _, seed := range []string{"", "fn unfinished(\nfn valid() -> Int:\n    return 1\n", "type Box:\n    value: String\n", "# 😀\r\nfn read() -> Int:\r\n    return 2\r\n", "fn (\n", "export type [\n"} {
		f.Add(seed)
	}
	f.Add("interface Read[T]:\n    get broken ->\n    get callback -> fn(\nvalue: T,\n) -> T\n")
	f.Add("impl Read for Box:\r\n    get value -> Int:\r\n        let broken =\r\n    fn get() -> Int: self.value\r\n")
	f.Fuzz(func(t *testing.T, source string) {
		module, issues := ParsePartial("fuzz.ms", source)
		if module == nil || module.Source != source {
			t.Fatal("lost source")
		}
		for _, decl := range module.Declarations {
			if decl.Pos.Offset < 0 || decl.Pos.Offset > len(source) {
				t.Fatal("declaration outside source", decl.Pos)
			}
		}
		for _, issue := range issues {
			if issue.Position.Offset < 0 || issue.Position.Offset > len(source) {
				t.Fatal("diagnostic outside source", issue)
			}
		}
	})
}

func TestPartialGroupedImportsPreserveSymbolOffsets(t *testing.T) {
	source := "fn first() -> Int:\n    return 1\nimport {\nListBuilder,\nMapBuilder,\n} from \"@std/collections.ms\"\nfn broken(\nfn later() -> Int:\n    return 2\n"
	module, issues := ParsePartial("grouped.ms", source)
	if len(issues) == 0 || len(module.Imports) != 2 || len(module.Declarations) != 2 {
		t.Fatal(module, issues)
	}
	for _, imp := range module.Imports {
		if imp.NamePos.Offset != strings.Index(source, imp.Name+",") {
			t.Fatal(imp)
		}
	}
}

func TestPartialDefaultsPreserveExpressionPositions(t *testing.T) {
	source := "fn broken(\nfn later(first: Int = 3, second: Int = first + 1) -> Int:\n    return second\n"
	module, issues := ParsePartial("defaults.ms", source)
	if len(issues) == 0 || len(module.Declarations) != 1 {
		t.Fatal(module, issues)
	}
	value := module.Declarations[0].Params[1].Default
	if value.Left.Pos.Line != 2 || value.Left.Pos.Offset != strings.Index(source, "first +") || value.Right.Pos.Offset != strings.Index(source, "1)") {
		t.Fatal("default expression positions were not rebased", value)
	}
}

func TestPartialMultilineDeclarations(t *testing.T) {
	for _, ending := range []string{"\n", "\r\n"} {
		source := strings.ReplaceAll(`# prefix
fn first() -> Int:
    return 1
export fn echo(
value: String,
) -> String:
    return value
fn sum[
T,
](
left: Int,
right: Int,
) -> Int:
    return left + right
fn broken(
fn later() -> Int:
    return 2
`, "\n", ending)
		module, issues := ParsePartial("multiline.ms", source)
		if len(issues) != 1 || len(module.Declarations) != 4 {
			t.Fatalf("declarations: %v; diagnostics: %v", module.Declarations, issues)
		}
		for i, name := range []string{"first", "echo", "sum", "later"} {
			decl := module.Declarations[i]
			if decl.Name != name || decl.Pos.Offset != strings.Index(source, "fn "+name) {
				t.Fatalf("incorrect declaration: %+v", decl)
			}
			for _, param := range decl.Params {
				if param.Pos.Offset != strings.Index(source, param.Name+":") || param.Pos.Line != strings.Count(source[:param.Pos.Offset], "\n")+1 {
					t.Fatalf("incorrect parameter position: %+v", param)
				}
			}
		}
		if issues[0].Position.Offset != strings.Index(source, "fn later") {
			t.Fatal(issues)
		}
	}
}

func TestPartialMatchExpressionPositions(t *testing.T) {
	for _, ending := range []string{"\n", "\r\n"} {
		source := strings.ReplaceAll(`fn broken(
fn later(values: List[Int]) -> Int:
    let result = match values[0]:
        some(number):
            let doubled = number * 2
            doubled
        none: return 0
    return result
`, "\n", ending)
		module, issues := ParsePartial("match.ms", source)
		if len(issues) == 0 || len(module.Declarations) != 1 {
			t.Fatal(module, issues)
		}
		value := module.Declarations[0].Body[0].Value
		if value.Kind != "match" || value.Arms[0].Value.Pos.Offset != strings.LastIndex(source, "doubled") || value.Arms[1].Body[0].Value.Pos.Offset != strings.Index(source, "0"+ending) {
			t.Fatalf("match expression lost recovered positions: %+v", value)
		}
	}
}

func TestPartialIndexCandidatesOwnTheirPositions(t *testing.T) {
	source := `fn broken(
fn later(values: List[Int]) -> Unit:
    let field = values[holder . index]
    let nested = values[indices[index]]
`
	module, issues := ParsePartial("index.ms", source)
	if len(issues) == 0 || len(module.Declarations) != 1 {
		t.Fatal(module, issues)
	}
	body := module.Declarations[0].Body
	field := body[0].Value.Right
	if field.Pos.Offset != strings.Index(source, "index]") {
		t.Fatal("field position ignored spaces", field.Pos)
	}
	nested := body[1].Value
	offset := strings.LastIndex(source, "index]")
	if nested.Types[0].Args[0].Pos.Offset != offset || nested.Right.Types[0].Pos.Offset != offset || nested.Right.Right.Pos.Offset != offset {
		t.Fatal("shared type arguments rebased twice", nested.Types[0].Args[0].Pos, nested.Right.Types[0].Pos, nested.Right.Right.Pos)
	}
}

func TestPartialRecoversAroundInvalidStatement(t *testing.T) {
	source := "fn work(a: Int) -> Int:\r\n    let b = a + 1\r\n    let c = = 3\r\n    if b > 0:\r\n        let d = )\r\n        let e = b\r\n    return b\r\n"
	module, issues := ParsePartial("source.ms", source)
	if len(module.Declarations) != 1 || len(module.Omitted) != 0 || len(issues) != 2 {
		t.Fatal(module.Declarations, module.Omitted, issues)
	}
	body := module.Declarations[0].Body
	if len(body) != 3 || body[0].Pos.Line != 2 || body[2].Pos.Offset != strings.Index(source, "return") {
		t.Fatal(body)
	}
	if len(module.Recovered) != 1 || module.Recovered[0].End != len(source) {
		t.Fatal(module.Recovered)
	}
}

func TestPartialOmitsDeclarationWithInvalidSignature(t *testing.T) {
	module, _ := ParsePartial("source.ms", "fn broken(a: ) -> Int:\n    return 1\nfn ok() -> Int:\n    return 2\n")
	if len(module.Declarations) != 1 || len(module.Omitted) != 1 || module.Omitted[0] != "broken" || len(module.Recovered) != 0 {
		t.Fatal(module)
	}
}

func TestPartialOmitsDeclarationWhenInvalidStatementIsAnEntireBlock(t *testing.T) {
	module, _ := ParsePartial("source.ms", "fn a() -> Int:\n    if true:\n        let y = = 3\n    return 1\n")
	if len(module.Declarations) != 0 || len(module.Omitted) != 1 {
		t.Fatal(module)
	}
}

func TestPartialReportsRecoveredIssuesInSourceOrder(t *testing.T) {
	_, issues := ParsePartial("source.ms", "fn a() -> Int:\n    if true:\n        let y = = 3\n        let z = 1\n    let w = = 4\n    return 1\n")
	for index := 1; index < len(issues); index++ {
		if issues[index].Position.Offset < issues[index-1].Position.Offset {
			t.Fatal(issues)
		}
	}
}

func TestPartialRecoversAroundUnterminatedDelimiter(t *testing.T) {
	for _, opener := range []string{"(", "[", "add(a: 1,"} {
		source := "fn add(a: Int, b: Int) -> Int:\r\n    return a + b\r\n\r\nexport fn main() -> Int:\r\n    let s = add(a: 1, b: 2)\r\n    let q = " + opener + "\r\n    return s\r\n"
		module, issues := ParsePartial("source.ms", source)
		if len(module.Declarations) != 2 || len(module.Omitted) != 0 || len(issues) != 1 {
			t.Fatal(opener, module.Declarations, module.Omitted, issues)
		}
		body := module.Declarations[1].Body
		if len(body) != 2 || body[0].Pos.Line != 5 || body[1].Pos.Offset != strings.Index(source, "return s") {
			t.Fatal(opener, body)
		}
		if !strings.Contains(issues[0].Message, "opened at line 6:") {
			t.Fatal("opener line not rebased", issues[0].Message)
		}
	}
}
