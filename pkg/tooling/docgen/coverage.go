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
	Entries                []DocumentationEntry `json:"entries"`
}

type DocumentationEntry struct {
	Module      string `json:"module"`
	Declaration string `json:"declaration"`
	Kind        string `json:"kind"`
	Name        string `json:"name"`
	Contract    string `json:"contract,omitempty"`
	Described   bool   `json:"described"`
}

func Inventory(modules []checker.APIModule) DocumentationInventory {
	report := DocumentationInventory{Format: 1, IncludesPreludeAliases: true, Entries: []DocumentationEntry{}}
	for _, module := range modules {
		for _, declaration := range module.Declarations {
			described := strings.TrimSpace(declaration.Doc) != ""
			report.Declarations++
			if described {
				report.DescribedDeclarations++
			}
			report.Entries = append(report.Entries, DocumentationEntry{Module: module.Path, Declaration: declaration.Name, Kind: "declaration", Name: declaration.Name, Described: described})
			for _, member := range declaration.Members {
				described := strings.TrimSpace(member.Doc) != ""
				report.Members++
				if described {
					report.DescribedMembers++
				}
				report.Entries = append(report.Entries, DocumentationEntry{Module: module.Path, Declaration: declaration.Name, Kind: member.Kind, Name: member.Name, Contract: member.Contract, Described: described})
			}
		}
	}
	return report
}
