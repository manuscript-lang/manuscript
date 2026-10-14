package docgen

import (
	"encoding/json"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/checker"
)

func TestMemberDescriptionsReachMarkdownAndCompatibleJSON(t *testing.T) {
	module := checker.APIModule{Path: "example.ms", Declarations: []checker.APIDeclaration{{Name: "Data", Kind: "record", Type: "Data", Declaration: "type Data:\n    value: Int\n", Fields: []string{"value: Int"}, Cases: []string{"Ready(value: Int)"}, Operations: []string{"read: fn()->Int"}, Members: []checker.APIMember{
		{Name: "value", Kind: "field", Signature: "value: Int", Doc: "The **stored** count.\n\nMeasured in items."},
		{Name: "Ready", Kind: "case", Signature: "case Ready(value: Int)", Doc: "Completed work."},
		{Name: "read", Kind: "operation", Signature: "fn read() -> Int", Doc: "Reads without mutation."},
		{Name: "missing", Kind: "field", Signature: "missing: Int"},
	}}}}
	for _, output := range []string{RenderModule(module), renderModule(module, true)} {
		for _, want := range []string{"### Data.value", "The **stored** count.\n\nMeasured in items.", "### Data.Ready", "Completed work.", "### Data.read", "Reads without mutation.", "fn read() -> Int"} {
			if !strings.Contains(output, want) {
				t.Fatalf("missing %q: %s", want, output)
			}
		}
		if strings.Contains(output, "### Data.missing") {
			t.Fatal("undocumented member fabricated a description")
		}
	}
	data, err := JSON([]checker.APIModule{module})
	if err != nil {
		t.Fatal(err)
	}
	var legacy struct {
		Format  int
		Modules []struct {
			Declarations []struct{ Fields, Cases, Operations []string }
		}
	}
	if err := json.Unmarshal(data, &legacy); err != nil {
		t.Fatal(err)
	}
	if legacy.Format != 1 || legacy.Modules[0].Declarations[0].Fields[0] != "value: Int" || legacy.Modules[0].Declarations[0].Cases[0] != "Ready(value: Int)" || legacy.Modules[0].Declarations[0].Operations[0] != "read: fn()->Int" {
		t.Fatal(string(data))
	}
}

func TestDescriptionInventoryIncludesMissingMembers(t *testing.T) {
	modules := []checker.APIModule{{Path: "fixture.ms", Declarations: []checker.APIDeclaration{{Name: "Data", Doc: "A record.", Members: []checker.APIMember{{Name: "present", Kind: "field", Doc: "A value."}, {Name: "missing", Kind: "operation"}}}, {Name: "Missing"}}}}
	report := Inventory(modules)
	if report.Declarations != 2 || report.DescribedDeclarations != 1 || report.Members != 2 || report.DescribedMembers != 1 || len(report.Entries) != 4 {
		t.Fatal(report)
	}
	if report.Entries[2].Described || report.Entries[2].Name != "missing" {
		t.Fatal("missing description is not visible", report)
	}
	standard := Inventory(checker.StandardLibrary())
	if standard.Members == 0 || len(standard.Entries) != standard.Declarations+standard.Members {
		t.Fatal("inventory omitted part of the standard surface", standard)
	}
}
