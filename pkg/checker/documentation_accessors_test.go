package checker

import (
	"slices"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/parser"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func TestAccessorDocumentationKeepsValueAndCallableContractsSeparate(t *testing.T) {
	const source = `export interface Sized:
    # The current count, read again each time.
    get length -> Int
    fn inspect() -> Int

export type Buffer:
    count: Int

impl Sized for Buffer:
    # Reads the authoritative count.
    get length -> Int:
        return self.count
    fn inspect() -> Int:
        return self.count
`
	for _, newline := range []string{"\n", "\r\n"} {
		module, err := parser.Parse("accessors.ms", strings.ReplaceAll(source, "\n", newline))
		if err != nil {
			t.Fatal(err)
		}
		program := Check([]*syntax.Module{module}, nil)
		if len(program.Diagnostics) != 0 {
			t.Fatal(program.Diagnostics)
		}
		for _, d := range ModuleDocumentation(program)[0].Declarations {
			if !slices.Equal(d.Accessors, []string{"length: Int"}) || !slices.Equal(d.Operations, []string{"inspect: fn()->Int"}) {
				t.Fatalf("%s mixed accessor values with callable operations: %+v", d.Name, d)
			}
			var getter APIMember
			for _, member := range d.Members {
				if member.Name == "length" {
					getter = member
				}
			}
			if getter.Kind != "accessor" || !strings.HasPrefix(getter.Signature, "get length -> Int") || getter.Doc == "" {
				t.Fatalf("%s lost accessor syntax or comments: %+v", d.Name, getter)
			}
		}
	}
}

func TestErrorDocumentationRetainsEveryMessageMethod(t *testing.T) {
	ensureStandard()
	expected := map[string]bool{}
	for _, method := range append(append([]*Method{}, standardImplementations...), standardSourceMethods()...) {
		if method.Contract.String() == "Error" && method.Decl.Name == "message" {
			expected[method.Receiver.Name] = true
		}
	}
	documented := map[string]bool{}
	for _, module := range StandardLibrary() {
		for _, declaration := range module.Declarations {
			for _, member := range declaration.Members {
				if member.Name != "message" || member.Contract != "Error" && declaration.Name != "Error" {
					continue
				}
				documented[declaration.Name] = true
				if member.Kind != "operation" || member.Signature != "fn message() -> String:" && member.Signature != "fn message() -> String" {
					t.Fatalf("%s.%s changed Error.message's method contract: %+v", module.Path, declaration.Name, member)
				}
				if slices.Contains(declaration.Accessors, "message: String") {
					t.Fatalf("%s.%s exposed Error.message as an accessor", module.Path, declaration.Name)
				}
			}
		}
	}
	if len(expected) == 0 {
		t.Fatal("no Error.message implementations discovered")
	}
	for name := range expected {
		if !documented[name] {
			t.Fatalf("missing Error.message method documentation for %s", name)
		}
	}
}
