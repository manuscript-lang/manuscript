// Package lsp implements the Manuscript language server over framed JSON-RPC.
package lsp

import (
	"encoding/json"
	"fmt"
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"github.com/manuscript-lang/manuscript/pkg/tooling"
	"io"
	"net/url"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"unicode/utf16"
)

type position struct {
	Line      int `json:"line"`
	Character int `json:"character"`
}
type span struct {
	Start position `json:"start"`
	End   position `json:"end"`
}
type document struct {
	URI     string `json:"uri"`
	Text    string `json:"text"`
	Version int    `json:"version"`
}

// Position converts an original byte offset to the LSP UTF-16 coordinate system.
func Position(source string, offset int) position {
	if offset < 0 {
		offset = 0
	}
	if offset > len(source) {
		offset = len(source)
	}
	prefix := source[:offset]
	line := strings.Count(prefix, "\n")
	tail := prefix[strings.LastIndex(prefix, "\n")+1:]
	return position{line, len(utf16.Encode([]rune(tail)))}
}

func Serve(input io.Reader, output io.Writer) error {
	transport := newTransport(input)
	defer transport.close()
	docs := map[string]document{}
	shutdown := false
	snippets := false
	roots := []string{}
	cache := map[string]compiler.Result{}
	checkedDocument := func(d document) compiler.Result {
		if result, ok := cache[d.URI]; ok {
			return result
		}
		result := analyze(d, docs)
		cache[d.URI] = result
		return result
	}
	send := func(v any) error {
		b, e := json.Marshal(v)
		if e != nil {
			return e
		}
		_, e = fmt.Fprintf(output, "Content-Length: %d\r\n\r\n%s", len(b), b)
		return e
	}
	publish := func() error {
		uris := []string{}
		for uri := range docs {
			uris = append(uris, uri)
		}
		sort.Strings(uris)
		for _, uri := range uris {
			d := docs[uri]
			if isStandardLibraryURI(uri) {
				if e := send(map[string]any{"jsonrpc": "2.0", "method": "textDocument/publishDiagnostics", "params": map[string]any{"uri": uri, "version": d.Version, "diagnostics": []any{}}}); e != nil {
					return e
				}
				continue
			}
			checked := checkedDocument(d)
			diagnostics := []any{}
			for _, issue := range checked.Diagnostics {
				if m := module(checked, d); m != nil && issue.Position.File != m.File {
					continue
				}
				diagnostics = append(diagnostics, map[string]any{"range": diagnosticSpan(d.Text, issue.Position.Offset), "severity": 1, "source": "manuscript", "code": issue.Code(), "message": issue.Message})
			}
			advisories := tooling.Lint(filename(d.URI), d.Text)
			if m := module(checked, d); m != nil {
				for _, issue := range tooling.LintProgram(checked.Program) {
					if issue.Position.File == m.File {
						advisories = append(advisories, issue)
					}
				}
			}
			for _, issue := range advisories {
				diagnostics = append(diagnostics, map[string]any{"range": diagnosticSpan(d.Text, issue.Position.Offset), "severity": 2, "source": "manuscript-lint", "code": issue.Code, "message": issue.Message})
			}
			if e := send(map[string]any{"jsonrpc": "2.0", "method": "textDocument/publishDiagnostics", "params": map[string]any{"uri": d.URI, "version": d.Version, "diagnostics": diagnostics}}); e != nil {
				return e
			}
		}
		return nil
	}

	for {
		incoming, ok := <-transport.messages
		if !ok {
			return nil
		}
		if incoming.err != nil {
			if incoming.err == io.EOF {
				return nil
			}
			return incoming.err
		}
		body := incoming.body

		var msg struct {
			JSONRPC string          `json:"jsonrpc"`
			ID      json.RawMessage `json:"id"`
			Method  string          `json:"method"`
			Params  json.RawMessage `json:"params"`
		}
		if e := json.Unmarshal(body, &msg); e != nil {
			code := -32700
			message := "invalid JSON"
			if json.Valid(body) {
				code = -32600
				message = "invalid request"
			}
			if err := send(map[string]any{"jsonrpc": "2.0", "id": nil, "error": map[string]any{"code": code, "message": message}}); err != nil {
				return err
			}
			continue
		}
		if msg.JSONRPC != "2.0" || msg.Method == "" {
			if err := send(map[string]any{"jsonrpc": "2.0", "id": nil, "error": map[string]any{"code": -32600, "message": "invalid request"}}); err != nil {
				return err
			}
			transport.done(msg.ID)
			continue
		}

		var p struct {
			Query        string   `json:"query"`
			Range        span     `json:"range"`
			NewName      string   `json:"newName"`
			TextDocument document `json:"textDocument"`
			Position     position `json:"position"`
			Context      struct {
				Only               []string `json:"only"`
				IncludeDeclaration bool     `json:"includeDeclaration"`
			} `json:"context"`
			ContentChanges []struct {
				Text  string `json:"text"`
				Range *span  `json:"range"`
			} `json:"contentChanges"`
		}
		if len(msg.Params) > 0 {
			if e := json.Unmarshal(msg.Params, &p); e != nil {
				if len(msg.ID) > 0 {
					if err := send(map[string]any{"jsonrpc": "2.0", "id": msg.ID, "error": map[string]any{"code": -32602, "message": "invalid parameters"}}); err != nil {
						return err
					}
					transport.done(msg.ID)
				}
				continue
			}
		}
		var result any
		var rpcError any
		if shutdown && msg.Method != "exit" {
			if len(msg.ID) > 0 {
				if e := send(map[string]any{"jsonrpc": "2.0", "id": msg.ID, "error": map[string]any{"code": -32600, "message": "server has shut down"}}); e != nil {
					return e
				}
			}
			continue
		}
		switch msg.Method {
		case "initialize":
			var init struct {
				RootURI          string `json:"rootUri"`
				WorkspaceFolders []struct {
					URI string `json:"uri"`
				} `json:"workspaceFolders"`
				Capabilities struct {
					TextDocument struct {
						Completion struct {
							CompletionItem struct {
								SnippetSupport bool `json:"snippetSupport"`
							} `json:"completionItem"`
						} `json:"completion"`
					} `json:"textDocument"`
				} `json:"capabilities"`
			}
			_ = json.Unmarshal(msg.Params, &init)
			snippets = init.Capabilities.TextDocument.Completion.CompletionItem.SnippetSupport
			if init.RootURI != "" {
				roots = append(roots, filename(init.RootURI))
			}
			for _, folder := range init.WorkspaceFolders {
				roots = append(roots, filename(folder.URI))
			}
			result = map[string]any{"capabilities": map[string]any{"textDocumentSync": 2, "documentFormattingProvider": true, "workspaceSymbolProvider": true, "documentSymbolProvider": true, "semanticTokensProvider": map[string]any{"legend": map[string]any{"tokenTypes": tokenTypes, "tokenModifiers": []string{}}, "full": true}, "codeActionProvider": map[string]any{"codeActionKinds": []string{"source.fixAll.manuscript", "quickfix", "source.organizeImports"}}, "renameProvider": map[string]any{"prepareProvider": true}, "referencesProvider": true, "signatureHelpProvider": map[string]any{"triggerCharacters": []string{"(", ",", ":"}, "retriggerCharacters": []string{","}}, "foldingRangeProvider": true, "inlayHintProvider": true, "typeDefinitionProvider": true, "documentHighlightProvider": true, "hoverProvider": true, "definitionProvider": true, "completionProvider": map[string]any{"triggerCharacters": []string{".", ":", "/"}}, "positionEncoding": "utf-16"}, "serverInfo": map[string]string{"name": "manuscript", "version": "0.1.0"}}
		case "manuscript/standardLibrarySource":
			var err error
			result, err = standardLibrarySource(p.TextDocument.URI)
			if err != nil {
				rpcError = map[string]any{"code": -32602, "message": err.Error()}
			}
		case "initialized":
		case "shutdown":
			shutdown = true
		case "exit":
			if !shutdown {
				return fmt.Errorf("exit before shutdown")
			}
			return nil
		case "workspace/didChangeWatchedFiles":
			cache = map[string]compiler.Result{}
			if e := publish(); e != nil {
				return e
			}
		case "textDocument/didClose":
			delete(docs, p.TextDocument.URI)
			cache = map[string]compiler.Result{}
			if e := publish(); e != nil {
				return e
			}
			if e := send(map[string]any{"jsonrpc": "2.0", "method": "textDocument/publishDiagnostics", "params": map[string]any{"uri": p.TextDocument.URI, "diagnostics": []any{}}}); e != nil {
				return e
			}
		case "textDocument/didOpen", "textDocument/didChange":
			d := p.TextDocument
			if isStandardLibraryURI(d.URI) {
				if msg.Method == "textDocument/didChange" {
					continue
				}
				source, err := standardLibrarySource(d.URI)
				if err != nil {
					continue
				}
				d.Text = source
			}
			if msg.Method == "textDocument/didChange" {
				old, ok := docs[d.URI]
				if !ok || d.Version <= old.Version {
					continue
				}
				if len(p.ContentChanges) == 0 {
					continue
				}
				d.Text = old.Text
				valid := true
				for _, change := range p.ContentChanges {
					if change.Range == nil {
						d.Text = change.Text
						continue
					}
					start, e := Offset(d.Text, change.Range.Start)
					if e != nil {
						valid = false
						break
					}
					end, e := Offset(d.Text, change.Range.End)
					if e != nil || end < start {
						valid = false
						break
					}
					d.Text = d.Text[:start] + change.Text + d.Text[end:]
				}
				if !valid {
					continue
				}
			}
			docs[d.URI] = d
			cache = map[string]compiler.Result{}
			if e := publish(); e != nil {
				return e
			}
		case "textDocument/semanticTokens/full", "textDocument/codeAction":
			d, ok := docs[p.TextDocument.URI]
			if !ok {
				rpcError = map[string]any{"code": -32602, "message": "document is not open"}
				break
			}
			if msg.Method == "textDocument/semanticTokens/full" {
				result = semantic(d, checkedDocument(d))
			} else {
				if isStandardLibraryURI(d.URI) {
					result = []any{}
					break
				}
				result = editorActions(d, checkedDocument(d), p.Range, p.Context.Only)
			}
		case "textDocument/formatting":
			d, ok := docs[p.TextDocument.URI]
			if !ok {
				rpcError = map[string]any{"code": -32602, "message": "document is not open"}
				break
			}
			if isStandardLibraryURI(d.URI) {
				result = []any{}
				break
			}
			formatted, e := tooling.Format(filename(d.URI), d.Text)
			if e != nil {
				rpcError = map[string]any{"code": -32602, "message": e.Error()}
				break
			}
			result = []any{map[string]any{"range": span{position{}, Position(d.Text, len(d.Text))}, "newText": formatted}}
		case "textDocument/prepareRename", "textDocument/rename":
			d, ok := docs[p.TextDocument.URI]
			if !ok {
				rpcError = map[string]any{"code": -32602, "message": "document is not open"}
				break
			}
			checked := checkedDocument(d)
			if !checked.Success() {
				rpcError = map[string]any{"code": -32602, "message": "rename requires a checked document"}
				break
			}
			name := p.NewName
			if msg.Method == "textDocument/rename" && name == "" {
				rpcError = map[string]any{"code": -32602, "message": "new name is empty"}
				break
			}
			if msg.Method == "textDocument/prepareRename" {
				name = ""
			}
			var err error
			result, err = rename(checked, d, p.Position, name, docs)
			if err != nil {
				rpcError = map[string]any{"code": -32602, "message": err.Error()}
			}
		case "workspace/symbol":
			result = workspaceSymbols(docs, roots, p.Query)
		case "textDocument/signatureHelp":
			d, ok := docs[p.TextDocument.URI]
			if !ok {
				break
			}
			var err error
			result, err = signatureHelp(d, docs, p.Position)
			if err != nil {
				rpcError = map[string]any{"code": -32602, "message": err.Error()}
			}
		case "textDocument/foldingRange", "textDocument/inlayHint", "textDocument/typeDefinition", "textDocument/documentHighlight":
			d, ok := docs[p.TextDocument.URI]
			if !ok {
				break
			}
			checked := checkedDocument(d)
			switch msg.Method {
			case "textDocument/foldingRange":
				result = foldingRanges(d)
			case "textDocument/inlayHint":
				result = inlayHints(checked, d, p.Range)
			case "textDocument/typeDefinition":
				result = typeDefinition(checked, d, p.Position)
			case "textDocument/documentHighlight":
				highlights := []any{}
				if checked.Program != nil {
					for _, raw := range references(checked, d, p.Position, true) {
						loc := raw.(map[string]any)
						if filename(loc["uri"].(string)) == filename(d.URI) {
							highlights = append(highlights, map[string]any{"range": loc["range"], "kind": 2})
						}
					}
				}
				result = highlights
			}
		case "textDocument/completion":
			d, ok := docs[p.TextDocument.URI]
			if !ok {
				result = []completionItem{}
				break
			}
			var err error
			result, err = completionAt(d, docs, p.Position, snippets)
			if err != nil {
				rpcError = map[string]any{"code": -32602, "message": err.Error()}
			}
		case "textDocument/hover", "textDocument/definition", "textDocument/references":
			d, ok := docs[p.TextDocument.URI]
			if !ok {
				break
			}
			checked := checkedDocument(d)
			if checked.Program == nil {
				break
			}
			if msg.Method == "textDocument/references" {
				result = workspaceReferences(d, docs, p.Position, p.Context.IncludeDeclaration)

			} else {
				result = navigation(checked, d, p.Position, msg.Method)
			}
		case "textDocument/documentSymbol":
			d, ok := docs[p.TextDocument.URI]
			result = []any{}
			if ok {
				result = documentSymbols(checkedDocument(d), d)
			}

		default:
			if len(msg.ID) > 0 {
				rpcError = map[string]any{"code": -32601, "message": "method not supported"}
			}
		}
		if len(msg.ID) > 0 {
			if transport.canceled(msg.ID) {
				rpcError = map[string]any{"code": -32800, "message": "request canceled"}
			}
			transport.done(msg.ID)
			response := map[string]any{"jsonrpc": "2.0", "id": msg.ID}
			if rpcError != nil {
				response["error"] = rpcError
			} else {
				response["result"] = result
			}
			if e := send(response); e != nil {
				return e
			}
		}
	}
}
func filename(uri string) string {
	u, e := url.Parse(uri)
	if e != nil || u.Scheme != "file" {
		return uri
	}
	p := u.Path
	if runtime.GOOS == "windows" {
		if len(p) > 2 && p[0] == '/' && p[2] == ':' {
			p = p[1:]
		}
		if u.Host != "" && u.Host != "localhost" {
			p = "//" + u.Host + p
		}
	}
	return filepath.FromSlash(p)
}
