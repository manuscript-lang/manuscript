// Package lsp implements the Manuscript language server over framed JSON-RPC.
package lsp

import (
	"encoding/json"
	"errors"
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

// server holds the state of one language-server session.
type server struct {
	transport *transport
	output    io.Writer
	docs      map[string]document
	cache     map[string]compiler.Result
	roots     []string
	snippets  bool
	shutdown  bool
}

// errExit ends the session cleanly after the exit notification.
var errExit = errors.New("exit")

// request is one decoded client message.
type request struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      json.RawMessage `json:"id"`
	Method  string          `json:"method"`
	Params  json.RawMessage `json:"params"`
	params  requestParams
}

type requestParams struct {
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

func rpcFailure(code int, message string) map[string]any {
	return map[string]any{"code": code, "message": message}
}

func notOpen() map[string]any { return rpcFailure(-32602, "document is not open") }

func Serve(input io.Reader, output io.Writer) error {
	s := &server{transport: newTransport(input), output: output, docs: map[string]document{}, cache: map[string]compiler.Result{}}
	defer s.transport.close()
	for incoming := range s.transport.messages {
		if incoming.err != nil {
			if incoming.err == io.EOF {
				return nil
			}
			return incoming.err
		}
		if err := s.serve(incoming.body); err != nil {
			if err == errExit {
				return nil
			}
			return err
		}
	}
	return nil
}

func (s *server) send(v any) error {
	b, e := json.Marshal(v)
	if e != nil {
		return e
	}
	_, e = fmt.Fprintf(s.output, "Content-Length: %d\r\n\r\n%s", len(b), b)
	return e
}

func (s *server) checkedDocument(d document) compiler.Result {
	if result, ok := s.cache[d.URI]; ok {
		return result
	}
	result := analyze(d, s.docs)
	s.cache[d.URI] = result
	return result
}

// invalidate drops cached analyses after a document or file change.
func (s *server) invalidate() { s.cache = map[string]compiler.Result{} }

func (s *server) publishDiagnostics(uri string, version int, diagnostics []any) error {
	return s.send(map[string]any{"jsonrpc": "2.0", "method": "textDocument/publishDiagnostics", "params": map[string]any{"uri": uri, "version": version, "diagnostics": diagnostics}})
}

// publish sends diagnostics for every open document, in URI order.
func (s *server) publish() error {
	uris := []string{}
	for uri := range s.docs {
		uris = append(uris, uri)
	}
	sort.Strings(uris)
	for _, uri := range uris {
		d := s.docs[uri]
		if isStandardLibraryURI(uri) {
			if e := s.publishDiagnostics(uri, d.Version, []any{}); e != nil {
				return e
			}
			continue
		}
		checked := s.checkedDocument(d)
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
		if e := s.publishDiagnostics(d.URI, d.Version, diagnostics); e != nil {
			return e
		}
	}
	return nil
}

// serve decodes one message, runs it, and sends the response a request expects.
func (s *server) serve(body []byte) error {
	var r request
	if e := json.Unmarshal(body, &r); e != nil {
		code, message := -32700, "invalid JSON"
		if json.Valid(body) {
			code, message = -32600, "invalid request"
		}
		return s.send(map[string]any{"jsonrpc": "2.0", "id": nil, "error": rpcFailure(code, message)})
	}
	if r.JSONRPC != "2.0" || r.Method == "" {
		err := s.send(map[string]any{"jsonrpc": "2.0", "id": nil, "error": rpcFailure(-32600, "invalid request")})
		s.transport.done(r.ID)
		return err
	}
	if len(r.Params) > 0 {
		if e := json.Unmarshal(r.Params, &r.params); e != nil {
			if len(r.ID) == 0 {
				return nil
			}
			err := s.send(map[string]any{"jsonrpc": "2.0", "id": r.ID, "error": rpcFailure(-32602, "invalid parameters")})
			s.transport.done(r.ID)
			return err
		}
	}
	if s.shutdown && r.Method != "exit" {
		if len(r.ID) > 0 {
			return s.send(map[string]any{"jsonrpc": "2.0", "id": r.ID, "error": rpcFailure(-32600, "server has shut down")})
		}
		return nil
	}
	result, rpcError, err := s.handle(&r)
	if err != nil {
		return err
	}
	if len(r.ID) == 0 {
		return nil
	}
	if s.transport.canceled(r.ID) {
		rpcError = rpcFailure(-32800, "request canceled")
	}
	s.transport.done(r.ID)
	response := map[string]any{"jsonrpc": "2.0", "id": r.ID}
	if rpcError != nil {
		response["error"] = rpcError
	} else {
		response["result"] = result
	}
	return s.send(response)
}

// handle routes a request to its method. It returns the result or the JSON-RPC
// error to answer with, and a non-nil error only when the session must end.
func (s *server) handle(r *request) (result any, rpcError any, err error) {
	p := &r.params
	switch r.Method {
	case "initialize":
		return s.initialize(r), nil, nil
	case "manuscript/standardLibrarySource":
		source, err := standardLibrarySource(p.TextDocument.URI)
		if err != nil {
			return nil, rpcFailure(-32602, err.Error()), nil
		}
		return source, nil, nil
	case "initialized":
		return nil, nil, nil
	case "shutdown":
		s.shutdown = true
		return nil, nil, nil
	case "exit":
		if !s.shutdown {
			return nil, nil, fmt.Errorf("exit before shutdown")
		}
		return nil, nil, errExit
	case "workspace/didChangeWatchedFiles":
		s.invalidate()
		return nil, nil, s.publish()
	case "textDocument/didClose":
		delete(s.docs, p.TextDocument.URI)
		s.invalidate()
		if err := s.publish(); err != nil {
			return nil, nil, err
		}
		return nil, nil, s.send(map[string]any{"jsonrpc": "2.0", "method": "textDocument/publishDiagnostics", "params": map[string]any{"uri": p.TextDocument.URI, "diagnostics": []any{}}})
	case "textDocument/didOpen", "textDocument/didChange":
		return nil, nil, s.didChange(r)
	case "workspace/symbol":
		return workspaceSymbols(s.docs, s.roots, p.Query), nil, nil
	}
	if !strings.HasPrefix(r.Method, "textDocument/") {
		if len(r.ID) > 0 {
			return nil, rpcFailure(-32601, "method not supported"), nil
		}
		return nil, nil, nil
	}
	result, rpcError = s.documentRequest(r)
	return result, rpcError, nil
}

// initialize records the client's roots and snippet support and answers with
// the server's capabilities.
func (s *server) initialize(r *request) any {
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
	_ = json.Unmarshal(r.Params, &init)
	s.snippets = init.Capabilities.TextDocument.Completion.CompletionItem.SnippetSupport
	if init.RootURI != "" {
		s.roots = append(s.roots, filename(init.RootURI))
	}
	for _, folder := range init.WorkspaceFolders {
		s.roots = append(s.roots, filename(folder.URI))
	}
	return map[string]any{"capabilities": map[string]any{"textDocumentSync": 2, "documentFormattingProvider": true, "workspaceSymbolProvider": true, "documentSymbolProvider": true, "semanticTokensProvider": map[string]any{"legend": map[string]any{"tokenTypes": tokenTypes, "tokenModifiers": []string{}}, "full": true}, "codeActionProvider": map[string]any{"codeActionKinds": []string{"source.fixAll.manuscript", "quickfix", "source.organizeImports"}}, "renameProvider": map[string]any{"prepareProvider": true}, "referencesProvider": true, "signatureHelpProvider": map[string]any{"triggerCharacters": []string{"(", ",", ":"}, "retriggerCharacters": []string{","}}, "foldingRangeProvider": true, "inlayHintProvider": true, "typeDefinitionProvider": true, "documentHighlightProvider": true, "hoverProvider": true, "definitionProvider": true, "completionProvider": map[string]any{"triggerCharacters": []string{".", ":", "/"}}, "positionEncoding": "utf-16"}, "serverInfo": map[string]string{"name": "manuscript", "version": "0.1.0"}}
}

// didChange stores an opened or edited document and republishes diagnostics.
// Stale, empty, or malformed edits are ignored.
func (s *server) didChange(r *request) error {
	p := &r.params
	d := p.TextDocument
	if isStandardLibraryURI(d.URI) {
		if r.Method == "textDocument/didChange" {
			return nil
		}
		source, err := standardLibrarySource(d.URI)
		if err != nil {
			return nil
		}
		d.Text = source
	}
	if r.Method == "textDocument/didChange" {
		old, ok := s.docs[d.URI]
		if !ok || d.Version <= old.Version || len(p.ContentChanges) == 0 {
			return nil
		}
		d.Text = old.Text
		for _, change := range p.ContentChanges {
			if change.Range == nil {
				d.Text = change.Text
				continue
			}
			start, e := editOffset(d.Text, change.Range.Start)
			if e != nil {
				return nil
			}
			end, e := editOffset(d.Text, change.Range.End)
			if e != nil || end < start {
				return nil
			}
			d.Text = d.Text[:start] + change.Text + d.Text[end:]
		}
	}
	s.docs[d.URI] = d
	s.invalidate()
	return s.publish()
}

// documentRequest answers the textDocument/* requests that read one open document.
func (s *server) documentRequest(r *request) (result any, rpcError any) {
	p := &r.params
	d, ok := s.docs[p.TextDocument.URI]
	switch r.Method {
	case "textDocument/semanticTokens/full":
		if !ok {
			return nil, notOpen()
		}
		return semantic(d, s.checkedDocument(d)), nil
	case "textDocument/codeAction":
		if !ok {
			return nil, notOpen()
		}
		if isStandardLibraryURI(d.URI) {
			return []any{}, nil
		}
		return editorActions(d, s.checkedDocument(d), p.Range, p.Context.Only), nil
	case "textDocument/formatting":
		if !ok {
			return nil, notOpen()
		}
		if isStandardLibraryURI(d.URI) {
			return []any{}, nil
		}
		formatted, e := tooling.Format(filename(d.URI), d.Text)
		if e != nil {
			return nil, rpcFailure(-32602, e.Error())
		}
		return []any{map[string]any{"range": span{position{}, Position(d.Text, len(d.Text))}, "newText": formatted}}, nil
	case "textDocument/prepareRename", "textDocument/rename":
		if !ok {
			return nil, notOpen()
		}
		return s.rename(r, d)
	case "textDocument/signatureHelp":
		if !ok {
			return nil, nil
		}
		help, err := signatureHelp(d, s.docs, p.Position)
		if err != nil {
			return nil, rpcFailure(-32602, err.Error())
		}
		return help, nil
	case "textDocument/foldingRange", "textDocument/inlayHint", "textDocument/typeDefinition", "textDocument/documentHighlight":
		if !ok {
			return nil, nil
		}
		return s.documentFeature(r, d), nil
	case "textDocument/completion":
		if !ok {
			return []completionItem{}, nil
		}
		items, err := completionAt(d, s.docs, p.Position, s.snippets)
		if err != nil {
			return nil, rpcFailure(-32602, err.Error())
		}
		return items, nil
	case "textDocument/hover", "textDocument/definition", "textDocument/references":
		if !ok {
			return nil, nil
		}
		checked := s.checkedDocument(d)
		if checked.Program == nil {
			return nil, nil
		}
		if r.Method == "textDocument/references" {
			return workspaceReferences(d, s.docs, p.Position, p.Context.IncludeDeclaration), nil
		}
		return navigation(checked, d, p.Position, r.Method), nil
	case "textDocument/documentSymbol":
		if !ok {
			return []any{}, nil
		}
		return documentSymbols(s.checkedDocument(d), d), nil
	}
	if len(r.ID) > 0 {
		return nil, rpcFailure(-32601, "method not supported")
	}
	return nil, nil
}

func (s *server) rename(r *request, d document) (any, any) {
	p := &r.params
	checked := s.checkedDocument(d)
	if !checked.Success() {
		return nil, rpcFailure(-32602, "rename requires a checked document")
	}
	name := p.NewName
	if r.Method == "textDocument/rename" && name == "" {
		return nil, rpcFailure(-32602, "new name is empty")
	}
	if r.Method == "textDocument/prepareRename" {
		name = ""
	}
	edit, err := rename(checked, d, p.Position, name, s.docs)
	if err != nil {
		return nil, rpcFailure(-32602, err.Error())
	}
	return edit, nil
}

// documentFeature answers the folding, inlay hint, type definition, and
// highlight requests, which share one checked document.
func (s *server) documentFeature(r *request, d document) any {
	p := &r.params
	checked := s.checkedDocument(d)
	switch r.Method {
	case "textDocument/foldingRange":
		return foldingRanges(d)
	case "textDocument/inlayHint":
		return inlayHints(checked, d, p.Range)
	case "textDocument/typeDefinition":
		return typeDefinition(checked, d, p.Position)
	}
	highlights := []any{}
	if checked.Program != nil {
		for _, raw := range references(checked, d, p.Position, true) {
			loc := raw.(map[string]any)
			if filename(loc["uri"].(string)) == filename(d.URI) {
				highlights = append(highlights, map[string]any{"range": loc["range"], "kind": 2})
			}
		}
	}
	return highlights
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
