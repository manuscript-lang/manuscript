package main

import (
	"context"
	// "encoding/json" // Keep if used by other parts not shown
	"log"
	"os"
	"strings" // Keep for folding/hover
	"sync"

	// *** THIS IS THE CRUCIAL IMPORT PATH FOR THE REAL PARSER ***
	// It assumes the 'internal/manuscript/parser' package is part of the 'manuscript-lsp-server' module
	// or is otherwise resolvable.
	parser "your_project_module/internal/manuscript/parser" // REAL PARSER IMPORT

	"golang.org/x/tools/gopls/jsonrpc2"
	"golang.org/x/tools/gopls/lsp/protocol"
)

// DummyManuscriptParser and DummyParseError are REMOVED.

type manuscriptServer struct {
	protocol.ServerHandler
	conn      *protocol.Server
	documents map[protocol.DocumentURI]*documentState
	mu        sync.Mutex
	parser    *parser.Parser // Use the real parser type
}

type documentState struct {
	uri     protocol.DocumentURI
	content string
	version int32
}

func newManuscriptServer(conn *protocol.Server) *manuscriptServer {
	return &manuscriptServer{
		conn:      conn,
		documents: make(map[protocol.DocumentURI]*documentState),
		// Initialize the real parser.
		// If parser.New() takes options or returns an error, adjust accordingly.
		parser: parser.New(), // Assuming a constructor like New() exists for the parser
	}
}

// --- Initialize, Initialized, DidOpen, DidChange, DidClose, Shutdown, Exit ---
// These handlers largely remain structurally the same, but DidOpen/DidChange will
// now rely on the real parser via validateDocument.

func (s *manuscriptServer) Initialize(ctx context.Context, params *protocol.InitializeParams) (*protocol.InitializeResult, error) {
	log.Println("Server: Initialize called (with real parser integration)")
	return &protocol.InitializeResult{
		Capabilities: protocol.ServerCapabilities{
			TextDocumentSync: protocol.TextDocumentSyncOptions{
				OpenClose: true,
				Change:    protocol.TextDocumentSyncKindFull,
			},
			CompletionProvider:   &protocol.CompletionOptions{},
			HoverProvider:        true,
			FoldingRangeProvider: true,
		},
	}, nil
}

func (s *manuscriptServer) Initialized(ctx context.Context, params *protocol.InitializedParams) error {
	log.Println("Server: Initialized notification received")
	return nil
}

func (s *manuscriptServer) DidOpen(ctx context.Context, params *protocol.DidOpenTextDocumentParams) error {
	docURI := params.TextDocument.URI
	log.Printf("Server: Document Opened: %s\n", docURI)
	s.mu.Lock()
	s.documents[docURI] = &documentState{
		uri:     docURI,
		content: params.TextDocument.Text,
		version: params.TextDocument.Version,
	}
	s.mu.Unlock()
	s.validateDocument(docURI, params.TextDocument.Text)
	return nil
}

func (s *manuscriptServer) DidChange(ctx context.Context, params *protocol.DidChangeTextDocumentParams) error {
	docURI := params.TextDocument.URI
	log.Printf("Server: Document Changed: %s\n", docURI)
	var content string
	if len(params.ContentChanges) == 1 && params.ContentChanges[0].Range == nil {
		content = params.ContentChanges[0].Text
	} else if len(params.ContentChanges) > 0 { // Should be full content due to TextDocumentSyncKindFull
        content = params.ContentChanges[0].Text
    } else {
		log.Printf("Warning: No content changes found for %s, cannot validate.", docURI)
		return nil
	}
	s.mu.Lock()
	s.documents[docURI] = &documentState{
		uri:     docURI,
		content: content,
		// version: params.TextDocument.Version, // Not directly available on DidChangeTextDocumentParams.document
	}
	s.mu.Unlock()
	s.validateDocument(docURI, content)
	return nil
}

func (s *manuscriptServer) DidClose(ctx context.Context, params *protocol.DidCloseTextDocumentParams) error {
	docURI := params.TextDocument.URI
	log.Printf("Server: Document Closed: %s\n", docURI)
	s.mu.Lock()
	delete(s.documents, docURI)
	s.mu.Unlock()
	s.conn.Notify(ctx, protocol.PublishDiagnosticsNotification, &protocol.PublishDiagnosticsParams{
		URI:         docURI,
		Diagnostics: []protocol.Diagnostic{},
	})
	return nil
}

func (s *manuscriptServer) Shutdown(ctx context.Context) error {
	log.Println("Server: Shutdown called")
	return nil
}

func (s *manuscriptServer) Exit(ctx context.Context) error {
	log.Println("Server: Exit called")
	return nil
}

// validateDocument now uses the REAL parser (from the imported 'parser' package)
func (s *manuscriptServer) validateDocument(uri protocol.DocumentURI, text string) {
	log.Printf("Server: Validating %s with REAL parser\n", uri)

	// Call the actual Manuscript parser
	// The signature `Parse(uri protocol.DocumentURI, content []byte) []parser.ParseError` is assumed.
	// Adjust if the real parser takes different arguments or returns different error types.
	// The real parser might also return an `error` itself if parsing cannot even begin.
	parseErrors := s.parser.Parse(uri, []byte(text)) // This is the key change

	diagnostics := []protocol.Diagnostic{}
	if parseErrors != nil { // Check if the error slice itself is nil
		for _, pErr := range parseErrors {
			// Assuming pErr has methods: Line() int, Column() int, Length() int, Message() string
			// These need to match the actual API of your internal parser's error type.
			diag := protocol.Diagnostic{
				Severity: protocol.SeverityError,
				Range: protocol.Range{
					Start: protocol.Position{Line: uint32(pErr.Line()), Character: uint32(pErr.Column())},
					End:   protocol.Position{Line: uint32(pErr.Line()), Character: uint32(pErr.Column() + pErr.Length())},
				},
				Message: pErr.Message(),
				Source:  "manuscript-parser (real)",
			}
			diagnostics = append(diagnostics, diag)
		}
	}
	// Handle if s.parser.Parse itself returns an error (e.g., if it's `func(...) ([]ParseError, error)`)
	// else if err != nil { ... log err, maybe send a generic diagnostic ... }


	log.Printf("Server: Sending %d diagnostics for %s (from real parser)\n", len(diagnostics), uri)
	s.conn.Notify(context.Background(), protocol.PublishDiagnosticsNotification, &protocol.PublishDiagnosticsParams{
		URI:         uri,
		Diagnostics: diagnostics,
	})
}

// --- Completion, Hover, FoldingRange handlers remain unchanged from the previous step for now ---
// (They are still basic and would ideally use the real parser's output in the future)
func (s *manuscriptServer) Completion(ctx context.Context, params *protocol.CompletionParams) (*protocol.CompletionList, error) {
	log.Printf("Server: Completion requested for %s at %v:%v\n", params.TextDocument.URI, params.Position.Line, params.Position.Character)
	items := []protocol.CompletionItem{}; keywords := []string{"let", "fn", "type", "if", "else", "for", "return", "true", "false", "null"}; for _, kw := range keywords { items = append(items, protocol.CompletionItem{Label: kw, Kind:  protocol.KeywordCompletion, Detail: "Manuscript keyword"})}
	snippets := []protocol.CompletionItem{{Label: "fn (function)", Kind: protocol.SnippetCompletion, InsertText: "fn ${1:name}(${2:params}) ${3:ReturnType} {\n\t${0}\n}", Detail: "Define a function", Documentation: "Defines a new function."}}; items = append(items, snippets...)
	return &protocol.CompletionList{IsIncomplete: false, Items: items}, nil
}
func (s *manuscriptServer) Hover(ctx context.Context, params *protocol.HoverParams) (*protocol.Hover, error) {
	log.Printf("Server: Hover requested for %s at %v:%v\n", params.TextDocument.URI, params.Position.Line, params.Position.Character); s.mu.Lock(); docState, ok := s.documents[params.TextDocument.URI]; s.mu.Unlock(); var word = ""; if ok { lines := strings.Split(docState.content, "\n"); if int(params.Position.Line) < len(lines) { line := lines[int(params.Position.Line)]; wordsOnLine := strings.FieldsFunc(line, func(r rune) bool { return !strings.ContainsRune("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_", r) }); charCount := 0; for _, w := range wordsOnLine { if charCount <= int(params.Position.Character) && int(params.Position.Character) < charCount+len(w) { word = w; break }; charCount += len(w) + 1 }}}
	keywordDocs := map[string]string{"let": "Declares a variable...", "fn": "Declares a function..."}; if doc, ok := keywordDocs[word]; ok { return &protocol.Hover{Contents: protocol.MarkupContent{Kind: protocol.MarkdownMarkup, Value: "**" + word + "** (Keyword)\n\n" + doc}}, nil }
	return &protocol.Hover{Contents: protocol.MarkupContent{Kind: protocol.MarkdownMarkup, Value: "Hover (Go LSP)\nToken: `" + word + "`"}}, nil
}
func (s *manuscriptServer) FoldingRange(ctx context.Context, params *protocol.FoldingRangeTextDocumentParams) ([]protocol.FoldingRange, error) {
	docURI := params.TextDocument.URI; log.Printf("Server: FoldingRange for %s\n", docURI); s.mu.Lock(); doc, ok := s.documents[docURI]; s.mu.Unlock(); if !ok { return nil, nil }; lines := strings.Split(doc.content, "\n"); ranges := []protocol.FoldingRange{}; stack := []int{}; regionStack := []int{}; commentRegionStack := []int{}
	for i, line := range lines { trimmedLine := strings.TrimSpace(line); if strings.HasPrefix(trimmedLine, "//{region") || strings.HasPrefix(trimmedLine, "// #region") { regionStack = append(regionStack, i) } else if strings.HasPrefix(trimmedLine, "//}endregion") || strings.HasPrefix(trimmedLine, "// #endregion") { if len(regionStack) > 0 { startLine := regionStack[len(regionStack)-1]; regionStack = regionStack[:len(regionStack)-1]; if i > startLine { ranges = append(ranges, protocol.FoldingRange{StartLine: uint32(startLine), EndLine: uint32(i), Kind: protocol.RegionFoldingRange}) }}}
	if strings.Contains(trimmedLine, "/*") && !strings.Contains(trimmedLine, "*/") { commentRegionStack = append(commentRegionStack, i) }; if strings.Contains(trimmedLine, "*/") && !strings.Contains(trimmedLine, "/*") { if len(commentRegionStack) > 0 { startLine := commentRegionStack[len(commentRegionStack)-1]; commentRegionStack = commentRegionStack[:len(commentRegionStack)-1]; if i > startLine { ranges = append(ranges, protocol.FoldingRange{StartLine: uint32(startLine), EndLine: uint32(i), Kind: protocol.CommentFoldingRange})}}}
	if strings.Contains(line, "{") { stack = append(stack, i) }; if strings.Contains(line, "}") { if len(stack) > 0 { startLine := stack[len(stack)-1]; stack = stack[:len(stack)-1]; if i > startLine { ranges = append(ranges, protocol.FoldingRange{StartLine: uint32(startLine), EndLine: uint32(i), Kind: protocol.RegionFoldingRange}) }}}}
	return ranges, nil
}


func main() {
	log.SetOutput(os.Stderr)
	log.Println("Manuscript Language Server (Go) starting (integrating real parser)...")
	ctx := context.Background()
	stream := jsonrpc2.NewHeaderStream(os.Stdin, os.Stdout)
	jsonrpcConn := jsonrpc2.NewConn(stream)
	serverHandler := newManuscriptServer(nil) // conn will be set by protocol.NewServer
	lspServer := protocol.NewServer(jsonrpcConn, serverHandler)
	serverHandler.conn = lspServer
	if err := lspServer.Run(ctx); err != nil {
		log.Fatalf("LSP server failed: %v\n", err)
	}
	log.Println("Manuscript Language Server (Go) stopped.")
}
