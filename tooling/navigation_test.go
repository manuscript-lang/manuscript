package tooling_test

import (
	"github.com/manuscript-lang/manuscript/compiler"
	"github.com/manuscript-lang/manuscript/stdlib"
	"github.com/manuscript-lang/manuscript/tooling"
	"strings"
	"testing"
)

func TestStandardLibraryNavigation(t *testing.T) {
	source := `import List from "@std/collections.ms"
import system from "@std/system.ms"
fn length(values: List[Int]) -> Int:
    return values.length()
fn os_name() -> String:
    return system().info().os
`
	result := compiler.CompileSource("navigation.ms", source, compiler.Options{})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	for _, item := range []struct{ needle, file, definition string }{{"List from", "@std/collections.ms", "type List"}, {"List[Int]", "@std/collections.ms", "type List"}, {"length()", "@std/collections.ms", "length()"}, {"system()", "@std/system.ms", "fn system()"}, {"info()", "@std/system.ms", "info()"}, {".os", "@std/system.ms", "os:"}} {
		offset := strings.LastIndex(source, item.needle)
		if item.needle == ".os" {
			offset++
		}
		if offset < 0 {
			t.Fatal(item.needle)
		}
		nav, ok := tooling.NavigationAt(result.Program, "navigation.ms", offset)
		if !ok {
			t.Errorf("missing navigation for %s", item.needle)
			continue
		}
		if nav.Definition.File != item.file || nav.Hover == "" {
			t.Errorf("%s: %#v", item.needle, nav)
		}
		data, err := stdlib.Sources.ReadFile(strings.TrimPrefix(nav.Definition.File, "@std/"))
		if err != nil {
			t.Fatal(err)
		}
		if !strings.Contains(string(data[nav.Definition.Start:nav.Definition.End]), item.definition) {
			t.Errorf("wrong definition: %s", data[nav.Definition.Start:nav.Definition.End])
		}
	}
}

func TestGroupedImportNavigation(t *testing.T) {
	source := "import {\n    List,\n    Map,\n} from \"@std/collections.ms\"\n"
	result := compiler.CompileSource("navigation.ms", source, compiler.Options{})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	for _, name := range []string{"List", "Map"} {
		nav, ok := tooling.NavigationAt(result.Program, "navigation.ms", strings.Index(source, name))
		if !ok || nav.Definition.File != "@std/collections.ms" || !strings.HasPrefix(nav.Hover, name+":") {
			t.Fatalf("%s: %+v, %v", name, nav, ok)
		}
	}
	if _, ok := tooling.NavigationAt(result.Program, "navigation.ms", strings.Index(source, "{")); ok {
		t.Fatal("brace navigates to a symbol")
	}
}

func TestNativeGenericMethodNavigation(t *testing.T) {
	source := `import List from "@std/collections.ms"
fn label(value: Int) -> String:
    return "{value}"
test "methods":
    let labels = [1].map(transform: label)
    let convert = [2].map[String]
    let text = " hello ".trim()
`
	result := compiler.CompileSource("methods.ms", source, compiler.Options{})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	for _, item := range []struct{ needle, file, hover string }{
		{"map(transform:", "@std/collections.ms", "List[String]"},
		{"map[String]", "@std/collections.ms", "List[String]"},
		{"trim()", "@std/intrinsics.ms", "fn()->String"},
	} {
		navigation, ok := tooling.NavigationAt(result.Program, "methods.ms", strings.Index(source, item.needle))
		if !ok || navigation.Definition.File != item.file || !strings.Contains(navigation.Hover, item.hover) {
			t.Fatalf("%s: %#v", item.needle, navigation)
		}
	}
}

func TestCommonErrorNavigation(t *testing.T) {
	source := `import Error from "@std/errors.ms"
import JsonError from "@std/json.ms"
fn describe(cause: Error) -> String:
    match cause:
        JsonError(json):
            return json.message()
        _:
            return cause.message()
`
	result := compiler.CompileSource("common-errors.ms", source, compiler.Options{})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	for _, item := range []struct{ needle, file string }{
		{"import Error from", "@std/errors.ms"},
		{"JsonError(json)", "@std/json.ms"},
		{"json.message()", "@std/json.ms"},
		{"cause.message()", "@std/errors.ms"},
	} {
		offset := strings.LastIndex(source, item.needle)
		if strings.HasPrefix(item.needle, "import ") {
			offset += len("import ")
		}
		if strings.Contains(item.needle, ".message") {
			offset += strings.Index(item.needle, "message")
		}
		nav, ok := tooling.NavigationAt(result.Program, "common-errors.ms", offset)
		if !ok || nav.Definition.File != item.file {
			t.Fatalf("%s: %+v, %v", item.needle, nav, ok)
		}
	}
}

func TestUniversalToStringNavigation(t *testing.T) {
	source := "fn text[T](value: T) -> String:\n    return value.toString()\n"
	result := compiler.CompileSource("conversion.ms", source, compiler.Options{})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	nav, ok := tooling.NavigationAt(result.Program, "conversion.ms", strings.Index(source, "toString"))
	if !ok || nav.Definition.File != "@std/intrinsics.ms" || !strings.Contains(nav.Hover, "fn()->String") {
		t.Fatal("universal method must navigate to its source signature", nav, ok)
	}
	effects := result.Program.Effects[result.Program.Symbols["conversion.ms"]["text"].ID]
	if len(effects) != 1 || effects[0] != "read" {
		t.Fatal("string conversion reads mutable data without invoking resources", effects)
	}
}

func TestNavigationWithinStandardLibrary(t *testing.T) {
	result := compiler.CompileSource("navigation.ms", "", compiler.Options{AnalyzeOnly: true})
	for _, item := range []struct{ file, needle, target, name string }{
		{"collections.ms", "Optional from", "optional.ms", "Optional"},
		{"collections.ms", "Optional[T]", "optional.ms", "Optional"},
		{"collections.ms", "List[T]) ->", "collections.ms", "List"},
		{"cli.ms", "List from", "collections.ms", "List"},
		{"cli.ms", "List[String]", "collections.ms", "List"},
	} {
		t.Run(item.file+"/"+item.needle, func(t *testing.T) {
			data, err := stdlib.Sources.ReadFile(item.file)
			if err != nil {
				t.Fatal(err)
			}
			offset := strings.LastIndex(string(data), item.needle)
			if offset < 0 {
				t.Fatal("missing source reference")
			}
			nav, ok := tooling.NavigationAt(result.Program, "@std/"+item.file, offset)
			if !ok || nav.Definition.File != "@std/"+item.target || nav.Hover == "" {
				t.Fatalf("missing standard navigation: %+v, %v", nav, ok)
			}
			target, err := stdlib.Sources.ReadFile(item.target)
			if err != nil {
				t.Fatal(err)
			}
			header := string(target[nav.Definition.Start:nav.Definition.End])
			if !strings.Contains(header, "type "+item.name) && !strings.Contains(header, "interface "+item.name) {
				t.Fatalf("wrong definition: %+v", nav)
			}
		})
	}
}
