package lsp

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestQuerySymbolFindsTypeDefinitionAndReferences(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "main.ms")
	source := "fn double(value: Int) -> Int:\n    return value * 2\n\nexport fn main() -> Int:\n    let x = double(4)\n    return x - 8\n"
	if err := os.WriteFile(path, []byte(source), 0o644); err != nil {
		t.Fatal(err)
	}
	// Line 5, column 13 is the call `double`.
	info, err := QuerySymbol(path, 5, 13)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(info.Hover, "double") || !strings.HasSuffix(info.Definition, "main.ms:1:4") {
		t.Errorf("hover %q definition %q", info.Hover, info.Definition)
	}
	if len(info.References) != 2 {
		t.Errorf("references = %v", info.References)
	}
	if _, err := QuerySymbol(path, 99, 1); err == nil {
		t.Error("line past end should fail")
	}
	if _, err := QuerySymbol(path, 0, 1); err == nil {
		t.Error("zero line should fail")
	}
}

func TestCharacterPositionCountsUTF16Units(t *testing.T) {
	p, err := characterPosition("let s = \"😀x\"\n", 1, 12)
	if err != nil || p.Line != 0 || p.Character != 12 {
		t.Fatalf("position = %+v, %v", p, err)
	}
}
