package lsp

import (
	"fmt"
	"github.com/manuscript-lang/manuscript/compiler"
	"github.com/manuscript-lang/manuscript/lexer"
	"sort"
	"strings"
)

func rename(result compiler.Result, d document, p position, name string, open ...map[string]document) (any, error) {
	selected := occurrenceAt(result, d, p)
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
		targets, err = workspaceDocuments(d, docs)
		if err != nil {
			return nil, err
		}
	}
	type replacement struct {
		start, end int
		newText    string
	}
	byURI := map[string][]replacement{}
	content := map[string]document{}
	hasDeclaration := false
	for _, target := range targets {
		checked := result
		if target.URI != d.URI {
			checked = workspaceAnalysis(target, docs)
		}
		if checked.Program == nil {
			continue
		}
		for _, entry := range sourceIndex(checked) {
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
				byURI[uri] = append(byURI[uri], replacement{entry.pos.Offset, entry.end, name})
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
	modified := copyDocuments(docs)
	changes := []any{}
	uris := []string{}
	for uri := range byURI {
		uris = append(uris, uri)
	}
	sort.Strings(uris)
	for _, uri := range uris {
		file := content[uri]
		tokens, e := lexer.Lex(filename(uri), file.Text)
		if e != nil {
			return nil, e
		}
		for _, token := range tokens {
			if token.Kind == lexer.Name && token.Text == name {
				return nil, fmt.Errorf("%s already occurs in %s; rename could capture another binding", name, filename(uri))
			}
		}
		edits := byURI[uri]
		sort.Slice(edits, func(i, j int) bool { return edits[i].start > edits[j].start })
		lspEdits := []any{}
		newSource := file.Text
		for _, edit := range edits {
			if edit.end > len(newSource) {
				return nil, fmt.Errorf("source revision changed")
			}
			lspEdits = append(lspEdits, map[string]any{"range": span{Position(file.Text, edit.start), Position(file.Text, edit.end)}, "newText": name})
			newSource = newSource[:edit.start] + name + newSource[edit.end:]
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
	// Validate the complete affected workspace snapshot before proposing any edit.
	// Signature labels, imports, constructors and type annotations participate in
	// the same index, so a rename cannot quietly break another module's contract.
	for _, target := range targets {
		before := workspaceAnalysis(target, docs)
		if !before.Success() {
			return nil, fmt.Errorf("rename requires a clean workspace: %s", filename(target.URI))
		}
		if updated, ok := modified[target.URI]; ok {
			target = updated
		}
		after := workspaceAnalysis(target, modified)
		if !after.Success() {
			message := "unknown checking failure"
			if len(after.Diagnostics) > 0 {
				message = after.Diagnostics[0].Message
			}
			return nil, fmt.Errorf("rename would break %s: %s", filename(target.URI), message)
		}
	}
	return map[string]any{"documentChanges": changes}, nil
}
