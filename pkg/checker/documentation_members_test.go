package checker

import (
	"encoding/json"
	"slices"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/parser"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func TestDocumentationCapturesMemberComments(t *testing.T) {
	source := `# A described record.
export type Counter:
    # Current count in items.
    # May start at zero.
    count: Int = 0
    # Detached description.

    undocumented: Int = 1

export type Outcome:
    # A completed count.
    case Ready(value: Int)
    # Work is pending.
    case Pending

export interface Countable:
    # Reads the count without mutation.
    fn count() -> Int

impl Countable for Counter:
    # Returns the stored count.
    fn count() -> Int:
        return self.count

# Private declarations stay private.
type Hidden:
    # Hidden member documentation.
    value: Int
`
	for _, newline := range []string{"\n", "\r\n"} {
		module, err := parser.Parse("members.ms", strings.ReplaceAll(source, "\n", newline))
		if err != nil {
			t.Fatal(err)
		}
		program := Check([]*syntax.Module{module}, nil)
		if len(program.Diagnostics) != 0 {
			t.Fatal(program.Diagnostics)
		}
		modules := ModuleDocumentation(program)
		declarations := map[string]APIDeclaration{}
		for _, d := range modules[0].Declarations {
			declarations[d.Name] = d
		}
		if len(declarations) != 3 {
			t.Fatal(declarations)
		}
		counter := declarations["Counter"]
		if !slices.Equal(counter.Fields, []string{"count: Int", "undocumented: Int"}) || !slices.Contains(counter.Operations, "count: fn()->Int") {
			t.Fatal("legacy contracts changed", counter)
		}
		members := map[string]APIMember{}
		for name, d := range declarations {
			for _, member := range d.Members {
				members[name+"/"+member.Kind+"/"+member.Name+"/"+member.Contract] = member
			}
		}
		for key, want := range map[string]string{
			"Counter/field/count/":              "Current count in items.\nMay start at zero.",
			"Counter/field/undocumented/":       "",
			"Counter/operation/count/Countable": "Returns the stored count.",
			"Outcome/case/Ready/":               "A completed count.",
			"Outcome/case/Pending/":             "Work is pending.",
			"Outcome/field/Ready.value/":        "",
			"Countable/operation/count/":        "Reads the count without mutation.",
		} {
			got, ok := members[key]
			if !ok || got.Doc != want {
				t.Errorf("%s: got %+v want %q", key, got, want)
			}
		}
		if members["Counter/field/count/"].Signature != "count: Int = 0" {
			t.Fatal("lost default")
		}
		data, err := json.Marshal(modules)
		if err != nil {
			t.Fatal(err)
		}
		var legacy []struct {
			Declarations []struct{ Fields, Cases, Operations []string }
		}
		if err := json.Unmarshal(data, &legacy); err != nil {
			t.Fatal("legacy JSON consumers cannot decode member arrays", err)
		}
		if !strings.Contains(string(data), `"members"`) || strings.Contains(string(data), "Hidden member documentation") {
			t.Fatal(string(data))
		}
	}
}

func TestStandardMemberCommentsIncludeIntrinsicAndNativeOperations(t *testing.T) {
	found := map[string]APIMember{}
	for _, module := range StandardLibrary() {
		for _, d := range module.Declarations {
			for _, member := range d.Members {
				found[module.Path+"/"+d.Name+"/"+member.Name] = member
			}
		}
	}
	for key, phrase := range map[string]string{
		"@std/bytes.ms/Bytes/values":      "fresh mutable list",
		"@std/collections.ms/List/map[U]": "",
		"prelude/String/slice":            "negative bounds are relative",
		"prelude/Float/to_fixed":          "binary64 ties to even",
	} {
		member, ok := found[key]
		if !ok || !strings.Contains(member.Doc, phrase) {
			t.Fatalf("missing member/source comment %s: %+v", key, member)
		}
	}
}

func TestEveryCheckedStandardMemberHasInventoryMetadata(t *testing.T) {
	for _, module := range StandardLibrary() {
		for _, d := range module.Declarations {
			members := map[string]bool{}
			for _, m := range d.Members {
				members[m.Kind+"/"+m.Name] = true
			}
			for kind, signatures := range map[string][]string{"field": d.Fields, "case": d.Cases, "operation": d.Operations} {
				for _, signature := range signatures {
					name, _, _ := strings.Cut(signature, ":")
					if kind == "operation" {
						name, _, _ = strings.Cut(signature, ": fn")
					}
					if kind == "case" {
						name, _, _ = strings.Cut(signature, "(")
					}
					if !members[kind+"/"+name] {
						t.Errorf("%s#%s omitted %s %s from description inventory", module.Path, d.Name, kind, name)
					}
				}
			}
		}
	}
}
