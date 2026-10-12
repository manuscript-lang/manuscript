package lsp

import (
	"bytes"
	"encoding/json"
	"fmt"
	"strings"
	"testing"
)

func frame(method string, id any, params any) string {
	message := map[string]any{"jsonrpc": "2.0", "method": method, "params": params}
	if id != nil {
		message["id"] = id
	}
	b, _ := json.Marshal(message)
	return fmt.Sprintf("Content-Length: %d\r\n\r\n%s", len(b), b)
}
func TestUTF16(t *testing.T) {
	s := "# 😀é\r\nfn"
	if got := Position(s, len("# 😀é")); got != (position{0, 5}) {
		t.Fatal(got)
	}
	if got := Position(s, len(s)); got != (position{1, 2}) {
		t.Fatal(got)
	}
}
func TestSession(t *testing.T) {
	source := "fn answer() -> Int:\n    return 42\n"
	input := frame("initialize", 1, map[string]any{}) + frame("textDocument/didOpen", nil, map[string]any{"textDocument": document{"file:///tmp/new.ms", source, 1}}) + frame("textDocument/formatting", 2, map[string]any{"textDocument": document{URI: "file:///tmp/new.ms"}}) + frame("textDocument/documentSymbol", 3, map[string]any{"textDocument": document{URI: "file:///tmp/new.ms"}}) + frame("shutdown", 4, nil) + frame("exit", nil, nil)
	var output bytes.Buffer
	if e := Serve(strings.NewReader(input), &output); e != nil {
		t.Fatal(e)
	}
	for _, want := range []string{"utf-16", "publishDiagnostics", "newText", "answer"} {
		if !strings.Contains(output.String(), want) {
			t.Fatalf("missing %s: %s", want, output.String())
		}
	}
}
func TestBadLength(t *testing.T) {
	for _, input := range []string{"Content-Length: -1\r\n\r\n", "Content-Length: 999999999\r\n\r\n", "Content-Length: 20\r\n\r\n{}"} {
		if Serve(strings.NewReader(input), &bytes.Buffer{}) == nil {
			t.Fatal("accepted invalid frame")
		}
	}
}

func TestSemanticTokensAndGuardedActions(t *testing.T) {
	d := document{"file:///tmp/new.ms", "fn answer() -> Int:\n    return 42", 9}
	tokens := semantic(d)["data"].([]int)
	if len(tokens) == 0 || len(tokens)%5 != 0 {
		t.Fatal(tokens)
	}
	list := actions(d)
	if len(list) != 1 {
		t.Fatal(list)
	}
	edit := list[0].(map[string]any)["edit"].(map[string]any)["documentChanges"].([]any)[0].(map[string]any)
	if edit["textDocument"].(map[string]any)["version"] != 9 {
		t.Fatal("missing edit version")
	}
	d.Text = "invalid syntax!"
	if len(actions(d)) != 0 {
		t.Fatal("offered edit for invalid syntax")
	}
}
func TestStaleVersionAndClose(t *testing.T) {
	uri := "file:///tmp/new.ms"
	input := frame("textDocument/didOpen", nil, map[string]any{"textDocument": document{uri, "fn answer() -> Int:\n    return 42\n", 2}}) + frame("textDocument/didChange", nil, map[string]any{"textDocument": document{URI: uri, Version: 1}, "contentChanges": []any{map[string]any{"text": "bad syntax!"}}}) + frame("textDocument/didClose", nil, map[string]any{"textDocument": document{URI: uri}}) + frame("shutdown", 1, nil) + frame("exit", nil, nil)
	var output bytes.Buffer
	if e := Serve(strings.NewReader(input), &output); e != nil {
		t.Fatal(e)
	}
	if strings.Count(output.String(), "publishDiagnostics") != 2 || strings.Contains(output.String(), "\"severity\":1") {
		t.Fatal(output.String())
	}
}
