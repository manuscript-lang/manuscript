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
				{Name: "example", Kind: tc.kind, Type: "fn(value: String)->Bool", Declaration: "fn example(value: String) -> Bool\n"},
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
				if strings.Contains(output, "Kind:") || !strings.Contains(output, "fn example(value: String) -> Bool") {
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
			if decoded.Format != 1 || decoded.Modules[0].Declarations[0].Kind != tc.kind || decoded.Modules[0].Declarations[0].Type != "fn(value: String)->Bool" || strings.Contains(string(data), "Declaration") {
				t.Fatalf("JSON must retain the raw compiler classification: %s", data)
			}
		})
	}
}

func TestSourceDeclarationsReachDocumentation(t *testing.T) {
	for _, module := range checker.StandardLibrary() {
		for _, output := range []string{renderModule(module, true), RenderModule(module)} {
			for _, d := range module.Declarations {
				if d.Declaration != "" && !strings.Contains(output, "```manuscript\n"+d.Declaration+"```") {
					t.Errorf("%s#%s lost its source declaration", module.Path, d.Name)
				}
			}
			for _, obsolete := range []string{"\noperation ", "\nfield ", "\ntype parameters:", "<unknown>"} {
				if strings.Contains(output, obsolete) {
					t.Errorf("%s contains checker formatting %q", module.Path, obsolete)
				}
			}
		}
		if module.Path == "@std/collections.ms" && !strings.Contains(renderModule(module, true), "## List {data-api-kind=\"Native type\"}") {
			t.Error("native receiver signatures must not label List as a source interface")
		}
		if module.Path == "@std/tasks.ms" {
			if !strings.Contains(renderModule(module, true), "## parallel {data-api-kind=\"Function\"}\n\nSee [special call rules](../call-rules.md).") {
				t.Error("compiler-bound parallel must link to its call rules")
			}
			if !strings.Contains(RenderModule(module), "See [special call rules](#special-call-rules).") {
				t.Error("portable reference must link to its included call rules")
			}
		}
	}
}
