package lsp

import (
	"context"
	"fmt"
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"github.com/manuscript-lang/manuscript/pkg/lexer"
	"sort"
	"strings"
)

func rename(result compiler.Result, d document, p position, name string, open ...map[string]document) (any, error) {
	return renameWithCancel(result, d, p, name, nil, open...)
}

func renameWithCancel(result compiler.Result, d document, p position, name string, canceled func() bool, open ...map[string]document) (any, error) {
	if isCanceled(canceled) {
		return nil, context.Canceled
	}
	return renameIndexed(result, sourceIndex(result), d, p, name, canceled, open...)
}

// Callers with a live checked index need not rebuild it for rename. The entry
// checkpoint also observes cancellation that arrived during index construction.
func renameIndexed(result compiler.Result, index []occurrence, d document, p position, name string, canceled func() bool, open ...map[string]document) (any, error) {
	if isCanceled(canceled) {
		return nil, context.Canceled
	}
	selected := occurrenceAt(result, d, p, index)
	if selected == nil {
		return nil, fmt.Errorf("select a resolved source declaration or use")
	}
	if strings.Contains(selected.key, ":@std/") {
		return nil, fmt.Errorf("standard-library declarations are read-only")
	}
	docs := map[string]document{d.URI: d}
	if len(open) > 0 {
		docs = copyDocuments(open[0])
		docs[d.URI] = d
	}
	targets := []document{d}
	if !strings.HasPrefix(selected.key, "binding:") {
		var err error
		targets, err = workspaceDocumentsWithCancel(d, docs, false, canceled)
		if err != nil {
			return nil, err
		}
	}
	byURI := map[string][]renameReplacement{}
	content := map[string]document{}
	hasDeclaration := false
	for _, target := range targets {
		if isCanceled(canceled) {
			return nil, context.Canceled
		}
		checked := result
		entries := index
		if target.URI != d.URI {
			checked = workspaceAnalysis(target, docs)
			if isCanceled(canceled) {
				return nil, context.Canceled
			}
			entries = sourceIndex(checked)
		}
		if isCanceled(canceled) {
			return nil, context.Canceled
		}
		if checked.Program == nil {
			continue
		}
		for _, entry := range entries {
			if entry.key != selected.key {
				continue
			}
			hasDeclaration = hasDeclaration || entry.declaration
			path := modulePath(checked, entry.pos.File)
			uri := fileURI(path)
			file, ok := content[uri]
			if !ok {
				for _, m := range checked.Program.Modules {
					if m.File == entry.pos.File {
						file = document{URI: uri, Text: m.Source}
						break
					}
				}
				if actual, opened := docs[uri]; opened {
					file = actual
				}
				content[uri] = file
			}
			exists := false
			for _, edit := range byURI[uri] {
				if edit.start == entry.pos.Offset {
					exists = true
					break
				}
			}
			if !exists {
				byURI[uri] = append(byURI[uri], renameReplacement{entry.pos.Offset, entry.end, name})
			}
		}
	}
	if !hasDeclaration {
		return nil, fmt.Errorf("declaration is external or has no editable source")
	}
	if name == "" {
		return map[string]any{"range": span{Position(d.Text, selected.pos.Offset), Position(d.Text, selected.end)}, "placeholder": selected.name}, nil
	}
	tokens, err := lexer.Lex("rename", name)
	if err != nil || len(tokens) == 0 || tokens[0].Kind != lexer.Name || tokens[0].Text != name {
		return nil, fmt.Errorf("new name must be a Manuscript identifier")
	}
	if name == selected.name {
		return map[string]any{"documentChanges": []any{}}, nil
	}
	modified, changes, err := renameChanges(docs, content, byURI, name, canceled)
	if err != nil {
		return nil, err
	}
	if err := validateRename(targets, docs, modified, canceled); err != nil {
		return nil, err
	}
	return map[string]any{"documentChanges": changes}, nil
}

type renameReplacement struct {
	start, end int
	newText    string
}

// Build one versioned edit per source file, stopping at each file boundary.
// Partial edits and modified overlays never escape a canceled phase.
func renameChanges(docs, content map[string]document, byURI map[string][]renameReplacement, name string, canceled func() bool) (map[string]document, []any, error) {
	modified := copyDocuments(docs)
	changes := []any{}
	uris := []string{}
	for uri := range byURI {
		uris = append(uris, uri)
	}
	sort.Strings(uris)
	for _, uri := range uris {
		if isCanceled(canceled) {
			return nil, nil, context.Canceled
		}
		file := content[uri]
		tokens, e := lexer.Lex(filename(uri), file.Text)
		if e != nil {
			return nil, nil, e
		}
		for _, token := range tokens {
			if token.Kind == lexer.Name && token.Text == name {
				return nil, nil, fmt.Errorf("%s already occurs in %s; rename could capture another binding", name, filename(uri))
			}
		}
		edits := byURI[uri]
		sort.Slice(edits, func(i, j int) bool { return edits[i].start > edits[j].start })
		lspEdits := []any{}
		newSource := file.Text
		for _, edit := range edits {
			if edit.end > len(newSource) {
				return nil, nil, fmt.Errorf("source revision changed")
			}
			lspEdits = append(lspEdits, map[string]any{"range": span{Position(file.Text, edit.start), Position(file.Text, edit.end)}, "newText": edit.newText})
			newSource = newSource[:edit.start] + edit.newText + newSource[edit.end:]
		}
		updated := file
		updated.Text = newSource
		modified[uri] = updated
		var version any
		if opened, ok := docs[uri]; ok {
			version = opened.Version
		}
		changes = append(changes, map[string]any{"textDocument": map[string]any{"uri": uri, "version": version}, "edits": lspEdits})
	}
	return modified, changes, nil
}

// Validate the complete affected workspace before proposing any edit.
func validateRename(targets []document, docs, modified map[string]document, canceled func() bool) error {
	// Signature labels, imports, constructors and type annotations participate in
	// the same index, so a rename cannot quietly break another module's contract.
	for _, target := range targets {
		if isCanceled(canceled) {
			return context.Canceled
		}
		before := workspaceAnalysis(target, docs)
		if isCanceled(canceled) {
			return context.Canceled
		}
		if !before.Success() {
			return fmt.Errorf("rename requires a clean workspace: %s", filename(target.URI))
		}
		if updated, ok := modified[target.URI]; ok {
			target = updated
		}
		after := workspaceAnalysis(target, modified)
		if isCanceled(canceled) {
			return context.Canceled
		}
		if !after.Success() {
			message := "unknown checking failure"
			if len(after.Diagnostics) > 0 {
				message = after.Diagnostics[0].Message
			}
			return fmt.Errorf("rename would break %s: %s", filename(target.URI), message)
		}
	}
	return nil
}
