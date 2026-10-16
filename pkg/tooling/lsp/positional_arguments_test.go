package lsp

import (
	"encoding/json"
	"path/filepath"
	"strings"
	"testing"
)

func TestPositionalSignatureHelp(t *testing.T) {
	for _, tc := range []struct {
		call   string
		active int
	}{
		{"subtract(10, |", 1},
		{"subtract(deduction: 3, |", 0},
		{"subtract(10, deduction: |", 1},
	} {
		result := signatureSource(t, "fn subtract(amount: Int, deduction: Int) -> Int: amount - deduction\nfn run() -> Int:\n    return "+tc.call+"\n")
		if result["activeParameter"] != tc.active {
			t.Fatal(tc.call, result)
		}
	}
}

func TestPositionalIdentifierRenameDoesNotAddLabels(t *testing.T) {
	source := "fn subtract(amount: Int, deduction: Int) -> Int: amount - deduction\nfn run() -> Int:\n    let number = 10\n    return subtract(number, 3)\n"
	d := document{fileURI(filepath.Join(t.TempDir(), "positional.ms")), source, 1}
	docs := map[string]document{d.URI: d}
	result := analyze(d, docs)
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	for _, tc := range []struct{ at, name, expanded string }{
		{"let number", "total", "total"},
		{"amount: Int", "total", "total"},
	} {
		offset := strings.Index(source, tc.at)
		if strings.HasPrefix(tc.at, "let ") {
			offset += 4
		}
		edit, err := rename(result, d, Position(source, offset), tc.name, docs)
		if err != nil {
			t.Fatal(err)
		}
		data, err := json.Marshal(edit)
		if err != nil || !strings.Contains(string(data), `"newText":"`+tc.expanded+`"`) || strings.Contains(string(data), ": total") || strings.Contains(string(data), "total: ") {
			t.Fatal(string(data), err)
		}
	}
}

func TestConstructorIdentifierRenameDoesNotAddLabels(t *testing.T) {
	for _, tc := range []struct{ declarations, call, at, expanded string }{
		{"type Pair:\n    first: Int\n    second: Int\n", "Pair(number, 3).first", "let number", "total"},
		{"type Pair:\n    first: Int\n    second: Int\n", "Pair(number, 3).first", "first: Int", "total"},
		{"type Pair:\n    case Values(first: Int, second: Int)\n", "Pair.Values(number, 3)", "let number", "total"},
	} {
		source := tc.declarations + "fn run() -> Unit:\n    let number = 10\n    let pair = " + tc.call + "\n"
		d := document{fileURI(filepath.Join(t.TempDir(), "constructor.ms")), source, 1}
		docs := map[string]document{d.URI: d}
		result := analyze(d, docs)
		if !result.Success() {
			t.Fatal(result.Diagnostics)
		}
		offset := strings.Index(source, tc.at)
		if strings.HasPrefix(tc.at, "let ") {
			offset += 4
		}
		edit, err := rename(result, d, Position(source, offset), "total", docs)
		if err != nil {
			t.Fatal(err)
		}
		data, err := json.Marshal(edit)
		if err != nil || !strings.Contains(string(data), `"newText":"`+tc.expanded+`"`) || strings.Contains(string(data), ": total") || strings.Contains(string(data), "total: ") {
			t.Fatal(string(data), err)
		}
	}
}
