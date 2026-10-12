package lsp

import "github.com/manuscript-lang/manuscript/compiler"

func references(result compiler.Result, d document, p position, includeDeclaration ...bool) []any {
	locations := []any{}
	selected := occurrenceAt(result, d, p)
	if selected == nil {
		return locations
	}
	include := len(includeDeclaration) > 0 && includeDeclaration[0]
	for _, entry := range sourceIndex(result) {
		if entry.key == selected.key && (include || !entry.declaration) {
			if location := occurrenceLocation(result, entry); location != nil {
				locations = append(locations, location)
			}
		}
	}
	return locations
}
