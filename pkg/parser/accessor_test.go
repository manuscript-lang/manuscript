package parser

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func TestAccessorDeclarations(t *testing.T) {
	const source = `# Keep original positions after non-ASCII comments: 😀
interface Read[T]:
    get value -> T
    get callback -> fn(value: T) -> T
    fn get() -> T
type Box[T]:
    get: T
impl Read[T] for Box[T]:
    get value -> T:
        return self.get
    get callback -> fn(value: T) -> T: fn(value: T) -> T: value
    fn get() -> T: self.get
type Native[T]:
    stored: T
    get value -> T:
    get is_empty -> Bool:
    fn get() -> T:
fn get(get: Int) -> Int:
    let value = get
    return value
`
	for _, ending := range []string{"\n", "\r\n"} {
		name := "LF"
		if ending == "\r\n" {
			name = "CRLF"
		}
		t.Run(name, func(t *testing.T) {
			text := strings.ReplaceAll(source, "\n", ending)
			module, err := Parse("accessors.ms", text)
			if err != nil {
				t.Fatal(err)
			}
			if len(module.Declarations) != 5 {
				t.Fatalf("declarations: %+v", module.Declarations)
			}
			for _, index := range []int{0, 2, 3} {
				owner := module.Declarations[index]
				if len(owner.Methods) != 3 {
					t.Fatalf("operations in %s: %+v", owner.Name, owner.Methods)
				}
				for i, operation := range owner.Methods {
					if operation.Kind != syntax.KindFn || operation.Accessor != (i < 2) || operation.Constant || len(operation.TypeParams) != 0 || len(operation.Params) != 0 || operation.Result == nil {
						t.Fatalf("incorrect operation: %+v", operation)
					}
					if text[operation.Pos.Offset:operation.Pos.Offset+len(operation.Name)] != operation.Name || operation.Pos.Line != strings.Count(text[:operation.Pos.Offset], "\n")+1 {
						t.Fatalf("operation name position: %+v", operation)
					}
					if (index == 2) != (len(operation.Body) == 1) {
						t.Fatalf("incorrect operation body: %+v", operation)
					}
				}
			}
			if callback := module.Declarations[0].Methods[1].Result; callback.Name != syntax.KindFn || len(callback.Params) != 1 || callback.Result.Name != "T" {
				t.Fatalf("function-valued accessor result: %+v", callback)
			}
			if field := module.Declarations[1].Fields[0]; field.Name != "get" || field.Type.Name != "T" {
				t.Fatalf("contextual get field: %+v", field)
			}
			if function := module.Declarations[4]; function.Accessor || function.Name != "get" || function.Params[0].Name != "get" {
				t.Fatalf("contextual get function: %+v", function)
			}
			if partial, issues := ParsePartial("accessors.ms", text); len(issues) != 0 || len(partial.Declarations) != len(module.Declarations) {
				t.Fatal(partial, issues)
			}
		})
	}
}

func TestRejectAccessorSyntax(t *testing.T) {
	for name, source := range map[string]string{
		"module accessor":           "get value -> Int: return 1\n",
		"exported module accessor":  "export get value -> Int: return 1\n",
		"local accessor":            "fn read() -> Int:\n    get value -> Int: return 1\n",
		"interface body":            "interface Read:\n    get value -> Int: return 1\n",
		"interface empty body":      "interface Read:\n    get value -> Int:\n",
		"interface parentheses":     "interface Read:\n    get value() -> Int\n",
		"interface parameters":      "interface Read:\n    get value(input: Int) -> Int\n",
		"interface own parameters":  "interface Read:\n    get value[T] -> T\n",
		"interface missing result":  "interface Read:\n    get value\n",
		"interface initializer":     "interface Read:\n    get value -> Int = 1\n",
		"impl parentheses":          "impl Read for Box:\n    get value() -> Int: return 1\n",
		"impl own type parameters":  "impl Read for Box:\n    get value[T] -> T: return self.value\n",
		"impl default":              "impl Read for Box:\n    get value(input: Int = 1) -> Int: return input\n",
		"impl missing colon":        "impl Read for Box:\n    get value -> Int\n",
		"impl missing result":       "impl Read for Box:\n    get value: return 1\n",
		"impl initializer":          "impl Read for Box:\n    get value -> Int = 1\n",
		"native own type parameter": "type Box:\n    get value[T] -> T:\n",
		"native missing colon":      "type Box:\n    get value -> Int\n",
		"accessor function type":    "fn use(value: get value -> Int) -> Unit: return\n",
	} {
		t.Run(name, func(t *testing.T) {
			if _, err := Parse("accessor.ms", source); err == nil {
				t.Fatal("accepted invalid accessor syntax")
			}
		})
	}
}

func TestAccessorSyntaxDiagnostics(t *testing.T) {
	for _, test := range []struct{ declaration, want string }{
		{"get value() -> Int", "accessors have no parameter list; write 'get value -> Type' without parentheses"},
		{"get value[T] -> T", "accessors cannot declare type parameters; use the receiver's type parameters in 'get value -> Type'"},
	} {
		_, err := Parse("accessor.ms", "interface Read:\n    "+test.declaration+"\n")
		issue, ok := err.(syntax.Diagnostic)
		if !ok || issue.Message != test.want || issue.Position.Line != 2 || issue.Position.Column != 14 {
			t.Fatalf("diagnostic for %s: %v", test.declaration, err)
		}
	}
}

func TestPartialAccessorsPreserveNeighboringOperations(t *testing.T) {
	const source = `# 😀
interface Read[T]:
    get callback -> fn(
value: T,
) -> T
    get broken ->
    get value -> T
type Box[T]:
    value: T
impl Read[T] for Box[T]:
    get broken -> Int:
        let missing =
    get value -> T:
        return self.value
fn later() -> Int: return 1
`
	for _, ending := range []string{"\n", "\r\n"} {
		text := strings.ReplaceAll(source, "\n", ending)
		if _, err := Parse("partial.ms", text); err == nil {
			t.Fatal("strict parser accepted incomplete accessor")
		}
		module, issues := ParsePartial("partial.ms", text)
		if len(issues) != 2 || len(module.Declarations) != 4 {
			t.Fatal(module, issues)
		}
		for _, index := range []int{0, 2} {
			owner := module.Declarations[index]
			if len(owner.Methods) != 2 || owner.Methods[1].Name != "value" || !owner.Methods[1].Accessor {
				t.Fatalf("lost neighboring accessor: %+v", owner.Methods)
			}
			value := owner.Methods[1]
			if value.Pos.Line != strings.Count(text[:value.Pos.Offset], "\n")+1 || text[value.Pos.Offset:value.Pos.Offset+5] != "value" {
				t.Fatalf("shifted accessor position: %+v", value)
			}
		}
		callback := module.Declarations[0].Methods[0]
		if callback.Result.Params[0].Pos.Offset != strings.Index(text, "value: T,") || callback.Result.Result.Pos.Offset != strings.Index(text, ") -> T")+5 {
			t.Fatalf("lost continued accessor result: %+v", callback.Result)
		}
		kept := module.Declarations[2].Methods[1].Body[0].Value
		if kept.Pos.Offset != strings.Index(text, "self.value")+5 || module.Declarations[3].Pos.Offset != strings.Index(text, "fn later") {
			t.Fatal("shifted accessor body or following declaration", kept.Pos, module.Declarations[3].Pos)
		}
	}
}
