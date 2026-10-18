package lsp

import (
	"strings"
	"testing"
)

// navigate resolves definition and hover at a byte offset of d. file is the
// definition's module ("@std/x.ms" for standard sources, the URI otherwise),
// and text runs from the declaration point to the end of its line.
func navigate(t *testing.T, d document, offset int) (file, text, hover string) {
	t.Helper()
	checked := analyze(d, map[string]document{d.URI: d})
	if !checked.Success() {
		t.Fatal(checked.Diagnostics)
	}
	pos := Position(d.Text, offset)
	if value, ok := navigation(checked, d, pos, "textDocument/hover").(map[string]any); ok {
		hover = value["contents"].(map[string]any)["value"].(string)
	}
	locations, ok := navigation(checked, d, pos, "textDocument/definition").([]any)
	if !ok || len(locations) == 0 {
		return "", "", hover
	}
	location := locations[0].(map[string]any)
	uri := location["uri"].(string)
	source := d.Text
	file = uri
	if isStandardLibraryURI(uri) {
		var err error
		if source, err = standardLibrarySource(uri); err != nil {
			t.Fatal(err)
		}
		file = "@std/" + strings.TrimPrefix(uri, "manuscript-stdlib:///")
	}
	start, err := Offset(source, location["range"].(span).Start)
	if err != nil {
		t.Fatal(err)
	}
	text = source[start:]
	if end := strings.IndexByte(text, '\n'); end >= 0 {
		text = text[:end]
	}
	return file, text, hover
}

func definitionAt(t *testing.T, source string, offset int) (file, text, hover string) {
	t.Helper()
	return navigate(t, document{"file:///tmp/navigation.ms", source, 1}, offset)
}

func TestStandardLibraryNavigation(t *testing.T) {
	source := `import ListBuilder from "@std/collections.ms"
import system from "@std/system.ms"
fn length(values: List[Int]) Int:
    return values.length()
fn os_name() String:
    return system().info().os
`
	for _, item := range []struct{ needle, file, definition string }{{"ListBuilder from", "@std/collections.ms", "ListBuilder[T]:"}, {"List[Int]", "@std/collections.ms", "List[T]:"}, {"length()", "@std/collections.ms", "length()"}, {"system()", "@std/system.ms", "system()"}, {"info()", "@std/system.ms", "info()"}, {".os", "@std/system.ms", "os:"}} {
		offset := strings.LastIndex(source, item.needle)
		if item.needle == ".os" {
			offset++
		}
		file, text, hover := definitionAt(t, source, offset)
		if file != item.file || hover == "" || !strings.Contains(text, item.definition) {
			t.Errorf("%s: %s %q %q", item.needle, file, text, hover)
		}
	}
}

func TestGroupedImportNavigation(t *testing.T) {
	source := "import {\n    ListBuilder,\n    MapBuilder,\n} from \"@std/collections.ms\"\n"
	for _, name := range []string{"ListBuilder", "MapBuilder"} {
		file, _, hover := definitionAt(t, source, strings.Index(source, name))
		if file != "@std/collections.ms" || !strings.Contains(hover, name+":") {
			t.Fatalf("%s: %s %q", name, file, hover)
		}
	}
	if file, _, _ := definitionAt(t, source, strings.Index(source, "{")); file != "" {
		t.Fatal("brace navigates to a symbol")
	}
}

func TestNativeGenericMethodNavigation(t *testing.T) {
	source := `fn label(value: Int) String:
    return "{value}"
test "methods":
    let labels = [1].map(transform: label)
    let convert = [2].map[String]
    let text = " hello ".trim()
`
	for _, item := range []struct{ needle, file, hover string }{
		{"map(transform:", "@std/collections.ms", "List[String]"},
		{"map[String]", "@std/collections.ms", "List[String]"},
		{"trim()", "@std/intrinsics.ms", "fn()->String"},
	} {
		file, _, hover := definitionAt(t, source, strings.Index(source, item.needle))
		if file != item.file || !strings.Contains(hover, item.hover) {
			t.Fatalf("%s: %s %q", item.needle, file, hover)
		}
	}
}

func TestBytesValuesNavigation(t *testing.T) {
	source := `import Bytes from "@std/bytes.ms"
fn extract(data: Bytes) List[Int]:
    let bound: fn() List[Int] = data.values
    return data.values()
`
	for _, offset := range []int{strings.Index(source, "values\n"), strings.Index(source, "values()")} {
		file, _, hover := definitionAt(t, source, offset)
		if file != "@std/bytes.ms" || !strings.Contains(hover, "fn()->List[Int]") {
			t.Fatalf("Bytes.values navigation lost callable signature: %s %q", file, hover)
		}
	}
}

func TestCommonErrorNavigation(t *testing.T) {
	source := `import JsonError from "@std/json.ms"
fn describe(cause: Error) String:
    match cause:
        JsonError(json):
            return json.message()
        _:
            return cause.message()
`
	// LSP resolves an interface-method call to a concrete implementation
	// rather than the contract in errors.ms, so cause.message() only asserts
	// that it lands on some standard message() declaration.
	for _, item := range []struct{ needle, file string }{
		{"Error) String", "@std/errors.ms"},
		{"JsonError(json)", "@std/json.ms"},
		{"json.message()", "@std/json.ms"},
		{"cause.message()", ""},
	} {
		offset := strings.LastIndex(source, item.needle)
		if strings.HasPrefix(item.needle, "import ") {
			offset += len("import ")
		}
		if strings.Contains(item.needle, ".message") {
			offset += strings.Index(item.needle, "message")
		}
		file, text, _ := definitionAt(t, source, offset)
		if item.file == "" && strings.HasPrefix(file, "@std/") && strings.HasPrefix(text, "message()") {
			continue
		}
		if file != item.file {
			t.Fatalf("%s: %q", item.needle, file)
		}
	}
}

func TestUniversalToStringNavigation(t *testing.T) {
	source := "fn text[T](value: T) String:\n    return value.to_string()\n"
	file, _, hover := definitionAt(t, source, strings.Index(source, "to_string"))
	if file != "@std/intrinsics.ms" || !strings.Contains(hover, "fn()->String") {
		t.Fatal("universal method must navigate to its source signature", file, hover)
	}
}

func TestSourceStandardLibraryNavigation(t *testing.T) {
	source := "import {parse, TomlValue} from \"@std/toml.ms\"\nfn read() Unit:\n    let result = parse(text: \"a=1\")\n"
	for _, offset := range []int{strings.Index(source, "parse"), strings.LastIndex(source, "parse("), strings.Index(source, "TomlValue")} {
		if file, _, _ := definitionAt(t, source, offset); file != "@std/toml.ms" {
			t.Fatal("missing source standard navigation", file)
		}
	}
	uri := "manuscript-stdlib:///toml.ms"
	standard, err := standardLibrarySource(uri)
	if err != nil {
		t.Fatal(err)
	}
	file, _, _ := navigate(t, document{uri, standard, 1}, strings.Index(standard, "parse_int, parse_float"))
	if file != "@std/numbers.ms" {
		t.Fatal("missing cross-standard source navigation", file)
	}
}

func TestConstructorNamesNavigateToCanonicalDeclarations(t *testing.T) {
	for _, tc := range []struct {
		name, module, expression string
	}{
		{"Set", "collections", "Set[String]()"},
		{"List", "collections", "List[String]()"},
		{"Map", "collections", "Map[String, Int]()"},
		{"Queue", "queues", "Queue[Int]()"},
		{"CsvOptions", "csv", `CsvOptions(delimiter: ",", line_ending: "\\n")`},
		{"Optional", "optional", "Optional[Int].some(1)"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			source := "fn example() Unit:\n    " + tc.expression + "\n"
			if tc.name == "Queue" || tc.name == "CsvOptions" {
				source = "import " + tc.name + " from \"@std/" + tc.module + ".ms\"\n" + source
			}
			file, _, _ := definitionAt(t, source, strings.LastIndex(source, tc.name))
			if file != "@std/"+tc.module+".ms" {
				t.Fatalf("constructor name did not resolve to its canonical declaration: %q", file)
			}
		})
	}
}

func TestDefaultCallNavigation(t *testing.T) {
	source := "fn read() Int:\n    return 1\nfn named(value: Int = read()) Int:\n    return value\n"
	file, text, _ := definitionAt(t, source, strings.Index(source, "read()"+")"))
	if file != "file:///tmp/navigation.ms" || !strings.HasPrefix(text, "read(") {
		t.Fatal("default call navigation", file, text)
	}
}
