package docgen

import (
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/checker"
)

// DocumentationInventory includes every rendered declaration and member,
// including prelude aliases. It records missing descriptions without inventing
// them or treating signature presence as descriptive coverage.
type DocumentationInventory struct {
	Format                 int                  `json:"format"`
	IncludesPreludeAliases bool                 `json:"includes_prelude_aliases"`
	Declarations           int                  `json:"declarations"`
	DescribedDeclarations  int                  `json:"described_declarations"`
	Members                int                  `json:"members"`
	DescribedMembers       int                  `json:"described_members"`
	QualifiedDeclarations  int                  `json:"qualified_declarations"`
	QualifiedMembers       int                  `json:"qualified_members"`
	Entries                []DocumentationEntry `json:"entries"`
}

type DocumentationEntry struct {
	Module      string `json:"module"`
	Declaration string `json:"declaration"`
	Kind        string `json:"kind"`
	Name        string `json:"name"`
	Contract    string `json:"contract,omitempty"`
	Described   bool   `json:"described"`
	Qualified   bool   `json:"qualified"`
	Problem     string `json:"problem,omitempty"`
}

func Inventory(modules []checker.APIModule) DocumentationInventory {
	report := DocumentationInventory{Format: 1, Entries: []DocumentationEntry{}}
	visitDescriptions(modules, func(entry DocumentationEntry, doc string) {
		entry.Described = strings.TrimSpace(doc) != ""
		entry.Problem = descriptionProblem(entry, doc)
		entry.Qualified = entry.Problem == ""
		if entry.Module == "prelude" {
			report.IncludesPreludeAliases = true
		}
		if entry.Kind == "declaration" {
			report.Declarations++
			if entry.Described {
				report.DescribedDeclarations++
			}
			if entry.Qualified {
				report.QualifiedDeclarations++
			}
		} else {
			report.Members++
			if entry.Described {
				report.DescribedMembers++
			}
			if entry.Qualified {
				report.QualifiedMembers++
			}
		}
		report.Entries = append(report.Entries, entry)
	})
	return report
}

func visitDescriptions(modules []checker.APIModule, visit func(DocumentationEntry, string)) {
	for _, module := range modules {
		for _, declaration := range module.Declarations {
			visit(DocumentationEntry{Module: module.Path, Declaration: declaration.Name, Kind: "declaration", Name: declaration.Name}, declaration.Doc)
			for _, member := range declaration.Members {
				visit(DocumentationEntry{Module: module.Path, Declaration: declaration.Name, Kind: member.Kind, Name: member.Name, Contract: member.Contract}, member.Doc)
			}
		}
	}
}
