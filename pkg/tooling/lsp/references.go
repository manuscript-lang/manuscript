package lsp

import "github.com/manuscript-lang/manuscript/pkg/compiler"

func references(result compiler.Result, d document, p position, includeDeclaration ...bool) []any {
	return referencesWithIndex(result, sourceIndex(result), d, p, len(includeDeclaration) > 0 && includeDeclaration[0])
}

func referencesWithIndex(result compiler.Result, index []occurrence, d document, p position, include bool) []any {
	locations := []any{}
	selected := occurrenceAt(result, d, p, index)
	if selected == nil {
		return locations
	}
	for _, entry := range index {
		if entry.key == selected.key && (include || !entry.declaration) {
			if location := occurrenceLocation(result, entry); location != nil {
				locations = append(locations, location)
			}
		}
	}
	return locations
}
