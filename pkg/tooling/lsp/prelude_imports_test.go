package lsp

import (
	"strings"
	"testing"
)

func TestCollectionSupportPreludeEditorContracts(t *testing.T) {
	for _, name := range []string{"CollectionError", "ListEntry", "MapEntry", "Equal", "Hashable"} {
		items := completeSource(t, "fn use(value: "+name[:3]+"|) -> Unit: unit\n")
		item := itemNamed(items, name)
		if item == nil || len(item.AdditionalTextEdits) != 0 {
			t.Fatal(name, item)
		}
	}
	for _, newline := range []string{"\n", "\r\n"} {
		source := strings.ReplaceAll("fn entries(values: List[Int]) -> List[ListEntry[Int]]: values.entries()\nfn pairs(values: Map[String, Int]) -> List[MapEntry[String, Int]]: values.entries()\nfn cut(values: List[Int]) -> Result[List[Int], CollectionError]: values.slice(0, 1)\n", "\n", newline)
		d := document{"file:///tmp/support.ms", source, 1}
		checked := analyze(d, map[string]document{d.URI: d})
		if !checked.Success() {
			t.Fatal(checked.Diagnostics)
		}
		for _, name := range []string{"ListEntry", "MapEntry", "CollectionError"} {
			target := navigation(checked, d, Position(source, strings.Index(source, name)), "textDocument/definition")
			if target == nil || target.([]any)[0].(map[string]any)["uri"] != "manuscript-stdlib:///collections.ms" {
				t.Fatal(name, target)
			}
		}
	}
	for _, source := range []string{"import |\n", "import {|} from \"@std/equality.ms\"\n", "import {|} from \"@std/errors.ms\"\n", "import {|} from \"@std/collections.ms\"\n"} {
		items := completeSource(t, source)
		for _, name := range []string{"Equal", "Hashable", "Error", "List", "Map", "Set", "ListEntry", "MapEntry", "CollectionError"} {
			if itemNamed(items, name) != nil {
				t.Fatal("offered redundant import", name, source)
			}
		}
	}
}

func TestRedundantPreludeImportEditorFix(t *testing.T) {
	for _, newline := range []string{"\n", "\r\n"} {
		for _, source := range []string{
			"import List from \"@std/collections.ms\" # keep\nfn count() -> Int: List[Int]().length()\n",
			"import {ListBuilder, List} from \"@std/collections.ms\"\nfn count() -> Int: ListBuilder[Int]().freeze().length()+List[Int]().length()\n",
			"import {\n    List, # keep\n    ListBuilder,\n} from \"@std/collections.ms\"\nfn count() -> Int: ListBuilder[Int]().freeze().length()+List[Int]().length()\n",
		} {
			source = strings.ReplaceAll(source, "\n", newline)
			d := document{"file:///tmp/imports.ms", source, 7}
			checked := analyze(d, map[string]document{d.URI: d})
			if checked.Success() || len(checked.Diagnostics) != 1 || checked.Diagnostics[0].Code() != "MS2003" {
				t.Fatal(checked.Diagnostics)
			}
			issue := checked.Diagnostics[0]
			pos := Position(source, issue.Position.Offset)
			actions := editorActions(d, checked, span{pos, pos}, []string{"quickfix"})
			if len(actions) != 1 {
				t.Fatal(actions)
			}
			action := actions[0].(map[string]any)
			if action["title"] != "Remove redundant prelude import" || action["isPreferred"] != true {
				t.Fatal(action)
			}
			change := action["edit"].(map[string]any)["documentChanges"].([]any)[0].(map[string]any)
			if change["textDocument"].(map[string]any)["version"] != 7 {
				t.Fatal(change)
			}
			edits := change["edits"].([]any)
			if len(edits) != 1 {
				t.Fatal(edits)
			}
			edit := edits[0].(map[string]any)
			r := edit["range"].(span)
			start, _ := Offset(source, r.Start)
			end, _ := Offset(source, r.End)
			d.Text = source[:start] + edit["newText"].(string) + source[end:]
			if !analyze(d, map[string]document{d.URI: d}).Success() {
				t.Fatal(d.Text)
			}
			if strings.Contains(source, "# keep") && !strings.Contains(d.Text, "# keep") {
				t.Fatal(d.Text)
			}
		}
	}
}

func TestPreludeImportCompletionSpacingAndRecovery(t *testing.T) {
	for _, newline := range []string{"\n", "\r\n"} {
		for _, source := range []string{
			"import{|}from \"@std/collections.ms\"\n",
			"import  { | }from \"@std/collections.ms\"\n",
			"import\t{\n    |\n}from \"@std/collections.ms\"\n",
			"import{\n    |\n}from \"@std/collections.ms\"\n",
		} {
			source = strings.ReplaceAll(source, "\n", newline)
			items := completeSource(t, source)
			if itemNamed(items, "ListBuilder") == nil {
				t.Fatal("lost real imports", source, items)
			}
			for _, name := range []string{"List", "Map", "Set", "CollectionError", "ListEntry", "MapEntry"} {
				if itemNamed(items, name) != nil {
					t.Fatal("offered redundant import", name, source)
				}
			}
		}
		for _, source := range []string{
			"import List from \"@std/collections.ms\"\nfn broken(\n",
			"fn bad() -> Unit:\n   unit\nimport {ListBuilder, List} from \"@std/collections.ms\"\n",
		} {
			source = strings.ReplaceAll(source, "\n", newline)
			d := document{"file:///tmp/recovery.ms", source, 1}
			checked := analyze(d, map[string]document{d.URI: d})
			pos := Position(source, strings.LastIndex(source, "List"))
			actions := editorActions(d, checked, span{pos, pos}, []string{"quickfix"})
			found := false
			for _, raw := range actions {
				if raw.(map[string]any)["title"] == "Remove redundant prelude import" {
					found = true
				}
			}
			if !found {
				t.Fatal("recovery lost removal action", source, checked.Diagnostics, actions)
			}
		}
	}
	items := completeSource(t, "import Name from \"@std/|\"\n")
	for _, path := range []string{"@std/optional.ms", "@std/result.ms", "@std/equality.ms"} {
		if itemNamed(items, path) != nil {
			t.Fatal("offered module with no importable declarations", path)
		}
	}
	if itemNamed(items, "@std/collections.ms") == nil || itemNamed(items, "@std/errors.ms") == nil {
		t.Fatal(items)
	}
}

func TestCompactApplicationImportCompletionKeepsSameNamedTypes(t *testing.T) {
	source := "import{|}from\"./prelude-local-types.ms\"\n"
	cursor := strings.Index(source, "|")
	source = strings.Replace(source, "|", "", 1)
	d := document{"file:///tmp/prelude-import-main.ms", source, 1}
	local := document{"file:///tmp/prelude-local-types.ms", "export type List[T]:\n    value: T\n", 1}
	items, err := completionAt(d, map[string]document{d.URI: d, local.URI: local}, Position(source, cursor), false)
	if err != nil || itemNamed(items, "List") == nil || itemNamed(items, "ListBuilder") != nil {
		t.Fatal(items, err)
	}
	items = completeSource(t, "import{\n    # a comment with \"quoted text\"\n    |\n}from\"@std/collections.ms\"\n")
	if itemNamed(items, "ListBuilder") == nil || itemNamed(items, "List") != nil {
		t.Fatal(items)
	}
}
