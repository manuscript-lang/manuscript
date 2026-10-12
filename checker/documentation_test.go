package checker

import (
	"encoding/json"
	"testing"
)

func TestStandardLibrarySnapshot(t *testing.T) {
	modules := StandardLibrary()
	exports := map[string]APIDeclaration{}
	count := 0
	for _, module := range modules {
		for _, d := range module.Declarations {
			exports[module.Path+"#"+d.Name] = d
			if module.Path != "prelude" {
				count++
			}
		}
	}
	expected := 0
	for _, symbols := range standardModules {
		for _, symbol := range symbols {
			if symbol.Export {
				expected++
			}
		}
	}
	if count != expected {
		t.Fatalf("captured %d exports, want %d", count, expected)
	}
	for _, key := range []string{"@std/collections.ms#List", "@std/tasks.ms#Background", "@std/cli.ms#Process", "prelude#String"} {
		d, ok := exports[key]
		if !ok {
			t.Fatalf("missing %s", key)
		}
		if key == "prelude#String" && len(d.Operations) != 3 {
			t.Fatalf("missing intrinsic operation: %+v", d)
		}
		if key == "@std/collections.ms#List" && (len(d.Parameters) != 1 || d.Parameters[0] != "T: Shareable" || len(d.Operations) != 4) {
			t.Fatalf("lost bounds or native methods: %+v", d)
		}
	}
	// Editing a snapshot must never change checker contracts.
	modules[0].Declarations[0].Name = "changed"
	again := StandardLibrary()
	if again[0].Declarations[0].Name == "changed" {
		t.Fatal("snapshot aliases registry")
	}
	a, _ := json.Marshal(again)
	b, _ := json.Marshal(StandardLibrary())
	if string(a) != string(b) {
		t.Fatal("output depends on map or candidate order")
	}
}
