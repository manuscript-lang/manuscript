package lsp

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"unicode/utf16"
)

// SymbolInfo describes the symbol at one source position.
type SymbolInfo struct {
	Hover       string   // type and documentation, as Markdown
	Definition  string   // file:line:column, or empty when none
	References  []string // file:line:column, declaration included
	Diagnostics int      // errors in the checked file; a broken file gives partial answers
}

// QuerySymbol answers hover, definition, and references for a 1-based line and
// column (a column counts characters) in a file, using the same analysis as the server.
func QuerySymbol(path string, line, column int) (SymbolInfo, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return SymbolInfo{}, err
	}
	abs, err := filepath.Abs(path)
	if err != nil {
		return SymbolInfo{}, err
	}
	d := document{URI: fileURI(abs), Text: string(data)}
	p, err := characterPosition(d.Text, line, column)
	if err != nil {
		return SymbolInfo{}, err
	}
	checked := analyze(d, map[string]document{})
	if checked.Program == nil {
		return SymbolInfo{}, fmt.Errorf("cannot analyze %s; run check for diagnostics", path)
	}
	info := SymbolInfo{Diagnostics: len(checked.Diagnostics)}
	if hover, ok := navigation(checked, d, p, "textDocument/hover").(map[string]any); ok {
		if contents, ok := hover["contents"].(map[string]any); ok {
			info.Hover, _ = contents["value"].(string)
		}
	}
	for _, location := range locations(navigation(checked, d, p, "textDocument/definition")) {
		info.Definition = location
		break
	}
	info.References = locations(workspaceReferences(d, map[string]document{}, p, true))
	return info, nil
}

// characterPosition converts a 1-based line and character column to an LSP position.
func characterPosition(text string, line, column int) (position, error) {
	if line < 1 || column < 1 {
		return position{}, fmt.Errorf("line and column are 1-based")
	}
	lines := strings.Split(text, "\n")
	if line > len(lines) {
		return position{}, fmt.Errorf("line %d is past the end of the file (%d lines)", line, len(lines))
	}
	runes := []rune(strings.TrimSuffix(lines[line-1], "\r"))
	if column > len(runes)+1 {
		return position{}, fmt.Errorf("column %d is past the end of line %d", column, line)
	}
	return position{Line: line - 1, Character: len(utf16.Encode(runes[:column-1]))}, nil
}

// locations flattens LSP location results into file:line:column strings.
func locations(result any) []string {
	data, err := json.Marshal(result)
	if err != nil {
		return nil
	}
	var many []struct {
		URI   string `json:"uri"`
		Range span   `json:"range"`
	}
	if err := json.Unmarshal(data, &many); err != nil {
		var one struct {
			URI   string `json:"uri"`
			Range span   `json:"range"`
		}
		if json.Unmarshal(data, &one) != nil || one.URI == "" {
			return nil
		}
		many = append(many, one)
	}
	out := make([]string, 0, len(many))
	for _, l := range many {
		out = append(out, fmt.Sprintf("%s:%d:%d", filename(l.URI), l.Range.Start.Line+1, l.Range.Start.Character+1))
	}
	return out
}
