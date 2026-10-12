package docgen

import (
	"encoding/json"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/checker"
)

func TestDeclarationKindPresentation(t *testing.T) {
	for _, tc := range []struct{ kind, label string }{
		{"fn", "Function"}, {"record", "Record"}, {"alternative", "Alternative"},
		{"interface", "Interface"}, {"type", "Type"}, {"native", "Native type"},
	} {
		t.Run(tc.kind, func(t *testing.T) {
			module := checker.APIModule{Path: "example.ms", Declarations: []checker.APIDeclaration{
				{Name: "example", Kind: tc.kind, Type: "fn(value: String)->Bool"},
			}}
			site := renderModule(module, true)
			if !strings.Contains(site, "## example {data-api-kind=\""+tc.label+"\"}") {
				t.Fatalf("missing badge metadata: %s", site)
			}
			portable := RenderModule(module)
			if !strings.Contains(portable, "**"+tc.label+"**") || strings.Contains(portable, "data-api-kind") {
				t.Fatalf("expected portable Markdown classification: %s", portable)
			}
			for _, output := range []string{site, portable} {
				if strings.Contains(output, "Kind:") || !strings.Contains(output, "example: fn(value: String)->Bool") {
					t.Fatalf("classification changed the signature or leaked a raw kind: %s", output)
				}
			}
			data, err := JSON([]checker.APIModule{module})
			if err != nil {
				t.Fatal(err)
			}
			var decoded struct {
				Format  int
				Modules []checker.APIModule
			}
			if err := json.Unmarshal(data, &decoded); err != nil {
				t.Fatal(err)
			}
			if decoded.Format != 1 || decoded.Modules[0].Declarations[0].Kind != tc.kind {
				t.Fatalf("JSON must retain the raw compiler classification: %s", data)
			}
		})
	}
}
