package lsp

import "github.com/manuscript-lang/manuscript/pkg/compiler"

func references(result compiler.Result, d document, p position, includeDeclaration ...bool) []any {
	locations := []any{}
	index := sourceIndex(result)
	selected := occurrenceAt(result, d, p, index)
	if selected == nil {
		return locations
	}
	include := len(includeDeclaration) > 0 && includeDeclaration[0]
	for _, entry := range index {
		if entry.key == selected.key && (include || !entry.declaration) {
			if location := occurrenceLocation(result, entry); location != nil {
				locations = append(locations, location)
			}
		}
	}
	return locations
}
