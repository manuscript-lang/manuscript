package compiler

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/checker"
)

func TestFullPublicCollectionAPIWithoutImports(t *testing.T) {
	// Exercise every source-backed operation, including generic callbacks and
	// named results, without making signature dependencies ambient by import.
	var source strings.Builder
	for _, name := range []string{"List", "Map", "Set"} {
		symbol := checker.StandardExports("@std/collections.ms")[name]
		receiver := map[string]string{"List": "List[String]", "Map": "Map[String, Int]", "Set": "Set[Int]"}[name]
		for _, method := range symbol.Decl.Methods {
			variables := map[string]string{"T": "String", "U": "Int"}
			if name == "Set" {
				variables["T"] = "Int"
			}
			for _, variable := range method.TypeParams {
				variables[variable.Name] = "Int"
			}
			var typ *checker.Type
			for _, operation := range symbol.Type.Def.Operations {
				if operation.Name == method.Name {
					typ = operation.Type
				}
			}
			if typ == nil {
				t.Fatal(name, method.Name)
			}
			fmt.Fprintf(&source, "fn %s_%s(receiver: %s", name, method.Name, receiver)
			args := []string{}
			for _, parameter := range typ.Params {
				fmt.Fprintf(&source, ", %s: %s", parameter.Name, collectionTypeSyntax(parameter.Type, variables))
				args = append(args, parameter.Name)
			}
			fmt.Fprintf(&source, ") -> %s: receiver.%s", collectionTypeSyntax(typ.Result, variables), method.Name)
			if len(method.TypeParams) > 0 {
				types := []string{}
				for range method.TypeParams {
					types = append(types, "Int")
				}
				fmt.Fprintf(&source, "[%s]", strings.Join(types, ", "))
			}
			fmt.Fprintf(&source, "(%s)\n", strings.Join(args, ", "))
		}
	}
	result := CompileSource("full-collection-api.ms", source.String(), Options{})
	if !result.Success() {
		t.Fatalf("%v\n%s", result.Diagnostics, source.String())
	}
}

func collectionTypeSyntax(typ *checker.Type, variables map[string]string) string {
	if typ.Kind == "variable" {
		return variables[typ.Name]
	}
	if typ.Kind == "function" {
		parameters := []string{}
		for _, p := range typ.Params {
			parameters = append(parameters, p.Name+": "+collectionTypeSyntax(p.Type, variables))
		}
		return "fn(" + strings.Join(parameters, ", ") + ") -> " + collectionTypeSyntax(typ.Result, variables)
	}
	result := typ.Name
	if len(typ.Args) > 0 {
		args := []string{}
		for _, arg := range typ.Args {
			args = append(args, collectionTypeSyntax(arg, variables))
		}
		result += "[" + strings.Join(args, ", ") + "]"
	}
	return result
}

func TestCollectionSupportShadowingAndCaseLookup(t *testing.T) {
	for name, source := range map[string]string{
		"qualified cases and directed patterns": `type Other:
    case OutOfRange
fn other() -> Other: Other.OutOfRange
fn standard() -> CollectionError: CollectionError.OutOfRange
fn recognize(value: Other) -> Int:
    match value:
        OutOfRange: return 1
`,
		"nonprelude imports": `import {ListBuilder, MapBuilder, SetBuilder, range, filled, map_from_entries} from "@std/collections.ms"
import {ErrorCategory, TextError, category} from "@std/errors.ms"
import Bytes from "@std/bytes.ms"
fn bytes() -> Bytes: Bytes([1])
fn build() -> List[Int]: ListBuilder[Int]().freeze()
fn text_error(message: String) -> TextError: TextError.Text(message)
`,
	} {
		t.Run(name, func(t *testing.T) {
			result := CompileSource("support.ms", source, Options{})
			if !result.Success() {
				t.Fatal(result.Diagnostics)
			}
		})
	}
	for name, source := range map[string]string{
		"ambiguous new case":           "type Other:\n    case OutOfRange\nfn get() -> Other: OutOfRange\n",
		"canonical entry is not local": "type ListEntry[T]:\n    payload: T\nfn get() -> List[ListEntry[Int]]: [1].entries()\n",
		"canonical error is not local": "type CollectionError:\n    case OutOfRange\nfn get() -> Result[List[Int], CollectionError]: [1].slice(0, 1)\n",
		"support bound":                "fn entries(values: MapEntry[List[Int], Int]) -> Unit: unit\n",
	} {
		t.Run(name, func(t *testing.T) {
			result := CompileSource("support.ms", source, Options{AnalyzeOnly: true})
			if result.Success() {
				t.Fatal("accepted invalid support use")
			}
			if name == "ambiguous new case" && !strings.Contains(result.Diagnostics[0].Message, "ambiguous alternative case") {
				t.Fatal(result.Diagnostics)
			}
		})
	}
}

func TestPreludeImportPolicyUsesResolvedIdentity(t *testing.T) {
	root := t.TempDir()
	files := map[string]string{
		"ms.toml":         "[project]\nname = \"prelude-test\"\nsource = \".\"\nentry = \"main.ms\"\n[aliases]\n\"@types\" = \"types.ms\"\n\"@domain\" = \"domain\"\n",
		"types.ms":        "export type List[T]:\n    value: T\nexport type Set[T]:\n    value: T\nexport type ListEntry[T]:\n    value: T\n",
		"domain/types.ms": "export type Map[K, V]:\n    value: V\nexport type MapEntry[K, V]:\n    value: V\nexport type CollectionError:\n    message: String\n",
		"main.ms":         "import {List, Set, ListEntry} from \"@types\"\nimport {Map, MapEntry, CollectionError} from \"@domain/types.ms\"\nfn get() -> Int: List(1).value + Set(2).value + Map[String, Int](3).value + ListEntry(4).value + MapEntry[String, Int](5).value\nfn cause() -> CollectionError: CollectionError(\"local\")\nexport fn main() -> Int: get() - 15\n",
	}
	for name, source := range files {
		path := filepath.Join(root, name)
		if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(source), 0600); err != nil {
			t.Fatal(err)
		}
	}
	result := CompileFile(filepath.Join(root, "ms.toml"), Options{AnalyzeOnly: true})
	if result.Success() || !strings.Contains(result.Diagnostics[0].Message, "reuses a prelude name") {
		t.Fatal("application imports named like prelude types were accepted", result.Diagnostics)
	}
	for _, path := range []string{"@std/unknown.ms", "@std/../collections.ms", "@std/collections.ms/unknown"} {
		result := CompileSource("imports.ms", "import List from \""+path+"\"\n", Options{AnalyzeOnly: true})
		if result.Success() {
			t.Fatal("accepted invalid standard path", path)
		}
		for _, issue := range result.Diagnostics {
			if issue.Code() == "MS2003" {
				t.Fatal("invalid path treated as prelude", issue)
			}
		}
	}
	result = CompileSource("imports.ms", "import {List, Map, Set} from \"@std/collections.ms\"\nfn get() -> Int: List[Int]().length()+Map[Int,Int]().length()+Set[Int]().length()\n", Options{AnalyzeOnly: true})
	if len(result.Diagnostics) != 3 || result.Source != "" {
		t.Fatal(result.Diagnostics, result.Source)
	}
	for _, issue := range result.Diagnostics {
		if issue.Code() != "MS2003" {
			t.Fatal(issue)
		}
	}
	for _, source := range []string{
		"import List as ImportedList from \"@std/collections.ms\"\n",
		"import {List as ImportedList} from \"@std/collections.ms\"\n",
		"export import List from \"@std/collections.ms\"\n",
	} {
		result := CompileSource("unsupported-import.ms", source, Options{AnalyzeOnly: true})
		if result.Success() || result.Source != "" {
			t.Fatal("unsupported import syntax bypassed the policy", source)
		}
		if result.Diagnostics[0].Phase != "parse" {
			t.Fatal("changed existing syntax rejection", result.Diagnostics)
		}
	}
}

func TestMissingValuePreludeDefaultsAndShadowing(t *testing.T) {
	for name, source := range map[string]string{
		"named default result": `fn first(values: List[Int]) -> Result[Int, MissingValue]: values.at(0).ok_or()
fn message(values: List[Int]) -> String: first(values).unwrap_error().message()
fn widen(cause: MissingValue) -> Error: cause
`,
		"qualified constructors and directed patterns": `type Other:
    case Missing(value: Int)
fn other() -> Other: Other.Missing(1)
fn standard() -> MissingValue: MissingValue.Missing("location")
fn read(value: Other) -> Int:
    match value:
        Missing(found): return found
`,
	} {
		t.Run(name, func(t *testing.T) {
			result := CompileSource("missing-prelude.ms", source, Options{})
			if !result.Success() {
				t.Fatal(result.Diagnostics)
			}
		})
	}
	result := CompileSource("missing-prelude.ms", "type Other:\n    case Missing(value: Int)\nfn get() -> Other: Missing(1)\n", Options{AnalyzeOnly: true})
	if result.Success() || !strings.Contains(result.Diagnostics[0].Message, "ambiguous alternative case") {
		t.Fatal("new ambient case lost normal ambiguity rules", result.Diagnostics)
	}
}
