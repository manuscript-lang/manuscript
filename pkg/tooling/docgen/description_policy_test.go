package docgen

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/checker"
)

func TestDescriptionGateRejectsPlaceholdersAndNameRestatements(t *testing.T) {
	entry := DocumentationEntry{Module: "fixture", Declaration: "Payload", Kind: "field", Name: "message"}
	for _, doc := range []string{"", " \n ", "TODO: add details later.", "Returns a value.", "This is the public message field.", "Documentation about the Payload message field.", "The message value as a String."} {
		if problem := descriptionProblem(entry, doc); problem == "" {
			t.Errorf("boilerplate passed: %q", doc)
		}
	}
	for _, doc := range []string{"Original host diagnostic text, returned unchanged by message().", "Maximum UTF-8 bytes in one record; none adds no budget.", "Returns a shallow copy; nested mutable references remain shared."} {
		if problem := descriptionProblem(entry, doc); problem != "" {
			t.Errorf("useful contract rejected: %q: %s", doc, problem)
		}
	}
}

func TestDescriptionGateRatchetsOnlyExactExistingGaps(t *testing.T) {
	modules := []checker.APIModule{{Path: "fixture", Declarations: []checker.APIDeclaration{{Name: "Payload", Doc: "Holds a host failure diagnostic.", Members: []checker.APIMember{{Name: "message", Kind: "field"}}}}}}
	report := Inventory(modules)
	key := DescriptionKey(report.Entries[1])
	policy := DescriptionPolicy{Format: 1, Backlog: []string{key}}
	if problems := CheckDescriptions(report, policy); len(problems) != 0 {
		t.Fatal(problems)
	}
	modules[0].Declarations[0].Members = append(modules[0].Declarations[0].Members, checker.APIMember{Name: "new_field", Kind: "field"})
	if problems := CheckDescriptions(Inventory(modules), policy); len(problems) != 1 || !strings.Contains(problems[0], "new_field") {
		t.Fatal("new gap was allowed", problems)
	}
	modules[0].Declarations[0].Members = modules[0].Declarations[0].Members[:1]
	modules[0].Declarations[0].Members[0].Doc = "This is the public message field."
	if problems := CheckDescriptions(Inventory(modules), policy); len(problems) != 2 {
		t.Fatal("backlog waived invalid prose or failed to shrink", problems)
	}
	modules[0].Declarations[0].Members[0].Doc = "Original host diagnostic text returned unchanged."
	if problems := CheckDescriptions(Inventory(modules), policy); len(problems) != 1 || !strings.Contains(problems[0], "stale backlog") {
		t.Fatal("described backlog entry survived", problems)
	}
	if problems := CheckDescriptions(Inventory(modules), DescriptionPolicy{Format: 1}); len(problems) != 0 {
		t.Fatal(problems)
	}
	modules[0].Declarations[0].Members = nil
	if problems := CheckDescriptions(Inventory(modules), policy); len(problems) != 1 || !strings.Contains(problems[0], "no longer exists") {
		t.Fatal("removed API bypassed backlog freshness", problems)
	}
}

func TestDescriptionInventoryDistinguishesPresenceFromQuality(t *testing.T) {
	report := Inventory([]checker.APIModule{{Path: "fixture", Declarations: []checker.APIDeclaration{{Name: "Payload", Doc: "A type.", Members: []checker.APIMember{{Name: "message", Kind: "field", Doc: "Original host diagnostic text returned unchanged."}}}}}})
	if report.DescribedDeclarations != 1 || report.QualifiedDeclarations != 0 || report.DescribedMembers != 1 || report.QualifiedMembers != 1 || report.IncludesPreludeAliases {
		t.Fatal(report)
	}
}
