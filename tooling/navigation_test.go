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
import Process from "@std/cli.ms"
fn length(values: List[Int]) -> Int:
    return values.length()
fn os_name(process: Process) -> String:
    return process.system.info().os
`
	result := compiler.CompileSource("navigation.ms", source, compiler.Options{})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	for _, item := range []struct{ needle, file, definition string }{{"List from", "@std/collections.ms", "type List"}, {"List[Int]", "@std/collections.ms", "type List"}, {"length()", "@std/collections.ms", "length()"}, {"system.info", "@std/cli.ms", "system:"}, {"info()", "@std/system.ms", "info()"}, {".os", "@std/system.ms", "os:"}} {
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
