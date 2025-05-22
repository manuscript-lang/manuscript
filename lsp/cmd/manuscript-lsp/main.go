package main

import (
	"context"
	// "encoding/json" // Not directly used in this snippet, but likely needed for real server
	"log"
	"os"
	"strings" // Added for string manipulation in folding/hover
	"sync"

	manuscriptparser "manuscript-lsp-server/internal/manuscript/parser" // Placeholder

	"golang.org/x/tools/gopls/jsonrpc2"
	"golang.org/x/tools/gopls/lsp/protocol"
)

// --- (DummyParseError and DummyManuscriptParser remain unchanged from previous step) ---
type DummyParseError struct { Line, Column, Length int; Message string }
type DummyManuscriptParser struct{}
func (p *DummyManuscriptParser) Parse(uri protocol.DocumentURI, content []byte) []DummyParseError {
	log.Printf("DummyManuscriptParser: Parsing %s\n", uri)
	errors := []DummyParseError{}
	if string(content[:]) == "error" {
		errors = append(errors, DummyParseError{ Line: 0, Column:  0, Length: 5, Message: "Dummy parse error: Found 'error' keyword."})
	}
	if len(content) > 80 {
         errors = append(errors, DummyParseError{ Line: 1, Column: 0, Length: 10, Message: "Dummy parse error: Line too long (placeholder)."})
    }
	return errors
}


type manuscriptServer struct {
	protocol.ServerHandler
	conn      *protocol.Server
	documents map[protocol.DocumentURI]*documentState
	mu        sync.Mutex
	parser    *DummyManuscriptParser
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
		parser:    &DummyManuscriptParser{},
	}
}

func (s *manuscriptServer) Initialize(ctx context.Context, params *protocol.InitializeParams) (*protocol.InitializeResult, error) {
	log.Println("Server: Initialize called")
	return &protocol.InitializeResult{
		Capabilities: protocol.ServerCapabilities{
			TextDocumentSync: protocol.TextDocumentSyncOptions{
				OpenClose: true,
				Change:    protocol.TextDocumentSyncKindFull,
			},
			CompletionProvider:   &protocol.CompletionOptions{},
			HoverProvider:        true,
			FoldingRangeProvider: true, // Added FoldingRangeProvider capability
		},
	}, nil
}

func (s *manuscriptServer) Initialized(ctx context.Context, params *protocol.InitializedParams) error {
	log.Println("Server: Initialized notification received")
	return nil
}

// --- (DidOpen, DidChange, DidClose, Shutdown, Exit, validateDocument remain unchanged from previous step) ---
func (s *manuscriptServer) DidOpen(ctx context.Context, params *protocol.DidOpenTextDocumentParams) error {
	docURI := params.TextDocument.URI; log.Printf("Server: Document Opened: %s\n", docURI)
	s.mu.Lock(); s.documents[docURI] = &documentState{ uri: docURI, content: params.TextDocument.Text, version: params.TextDocument.Version}; s.mu.Unlock()
	s.validateDocument(docURI, params.TextDocument.Text); return nil
}
func (s *manuscriptServer) DidChange(ctx context.Context, params *protocol.DidChangeTextDocumentParams) error {
	docURI := params.TextDocument.URI; log.Printf("Server: Document Changed: %s\n", docURI)
	var content string
	if len(params.ContentChanges) == 1 && params.ContentChanges[0].Range == nil { content = params.ContentChanges[0].Text
	} else if len(params.ContentChanges) > 0 { content = params.ContentChanges[0].Text
	} else { log.Printf("Warning: No content changes found for %s, cannot validate.", docURI); return nil }
	s.mu.Lock(); s.documents[docURI] = &documentState{ uri: docURI, content: content }; s.mu.Unlock()
	s.validateDocument(docURI, content); return nil
}
func (s *manuscriptServer) DidClose(ctx context.Context, params *protocol.DidCloseTextDocumentParams) error {
	docURI := params.TextDocument.URI; log.Printf("Server: Document Closed: %s\n", docURI)
	s.mu.Lock(); delete(s.documents, docURI); s.mu.Unlock()
	s.conn.Notify(ctx, protocol.PublishDiagnosticsNotification, &protocol.PublishDiagnosticsParams{ URI: docURI, Diagnostics: []protocol.Diagnostic{}}); return nil
}
func (s *manuscriptServer) Shutdown(ctx context.Context) error { log.Println("Server: Shutdown called"); return nil }
func (s *manuscriptServer) Exit(ctx context.Context) error { log.Println("Server: Exit called"); return nil }
func (s *manuscriptServer) validateDocument(uri protocol.DocumentURI, text string) {
	log.Printf("Server: Validating %s\n", uri); parseErrors := s.parser.Parse(uri, []byte(text)); diagnostics := []protocol.Diagnostic{}
	for _, pErr := range parseErrors {
		diagnostics = append(diagnostics, protocol.Diagnostic{ Severity: protocol.SeverityError, Range: protocol.Range{ Start: protocol.Position{Line: uint32(pErr.Line), Character: uint32(pErr.Column)}, End:   protocol.Position{Line: uint32(pErr.Line), Character: uint32(pErr.Column + pErr.Length)}}, Message: pErr.Message, Source:  "manuscript-parser"})
	}
	log.Printf("Server: Sending %d diagnostics for %s\n", len(diagnostics), uri)
	s.conn.Notify(context.Background(), protocol.PublishDiagnosticsNotification, &protocol.PublishDiagnosticsParams{ URI: uri, Diagnostics: diagnostics,})
}


// Enhanced Completion Handler
func (s *manuscriptServer) Completion(ctx context.Context, params *protocol.CompletionParams) (*protocol.CompletionList, error) {
	log.Printf("Server: Completion requested for %s at %v:%v\n", params.TextDocument.URI, params.Position.Line, params.Position.Character)
	
	items := []protocol.CompletionItem{}
	keywords := []string{
		"let", "fn", "return", "yield", "type", "interface", "extends", "import", "export", "extern",
		"if", "else", "for", "while", "in", "match", "case", "default",
		"check", "try", "async", "await", "go", "defer",
		"as", "void", "null", "true", "false",
		"bool", "string", "number", "i8", "i16", "i32", "i64", "int", "uint8", "uint16", "uint32", "uint64", "f32", "f64", "long", "double",
	}
	for _, kw := range keywords {
		items = append(items, protocol.CompletionItem{
			Label: kw,
			Kind:  protocol.KeywordCompletion,
			Detail: "Manuscript keyword",
		})
	}

	snippets := []protocol.CompletionItem{
		{
			Label: "fn (function)",
			Kind: protocol.SnippetCompletion,
			InsertText: "fn ${1:name}(${2:params}) ${3:ReturnType} {\n\t${0}\n}",
			Detail: "Define a function",
            Documentation: "Defines a new function with specified name, parameters, and return type.",
		},
		{
			Label: "let (variable)",
			Kind: protocol.SnippetCompletion,
			InsertText: "let ${1:name} = ${0:value}",
			Detail: "Declare a variable",
            Documentation: "Declares a new variable or constant binding.",
		},
        {
			Label: "if",
			Kind: protocol.SnippetCompletion,
			InsertText: "if ${1:condition} {\n\t${0}\n}",
			Detail: "If statement",
            Documentation: "Executes a block of code if the condition is true.",
		},
        {
			Label: "type (struct)",
			Kind: protocol.SnippetCompletion,
			InsertText: "type ${1:Name} {\n\t${0}\n}",
			Detail: "Define a new struct type",
            Documentation: "Defines a new struct (user-defined type).",
		},
	}
	items = append(items, snippets...)

	return &protocol.CompletionList{IsIncomplete: false, Items: items}, nil
}

// Enhanced Hover Handler
func (s *manuscriptServer) Hover(ctx context.Context, params *protocol.HoverParams) (*protocol.Hover, error) {
	log.Printf("Server: Hover requested for %s at %v:%v\n", params.TextDocument.URI, params.Position.Line, params.Position.Character)
	
	// For this basic version, we won't read the document to find the word.
	// A real version would:
	// 1. Get document content: s.documents[params.TextDocument.URI].content
	// 2. Find word at params.Position
	// 3. Look up word in keywordDocs or use internal parser for semantic info.

	// Simple keyword documentation
	keywordDocs := map[string]string{
		"let": "Declares a variable or constant binding. Usage: `let name = value`",
		"fn": "Declares a function. Usage: `fn name(params) ReturnType { ... }`",
		"type": "Defines a new struct type. Usage: `type Name { field: Type, ... }`",
		"if": "Conditional execution. Usage: `if condition { ... }`",
		"else": "Alternative execution for an if statement.",
		"for": "Looping construct. e.g., `for item in collection { ... }` or `for i=0; i<10; i++ { ... }`",
		"return": "Returns a value from a function.",
		"true": "Boolean true value.",
		"false": "Boolean false value.",
		"null": "Represents the absence of a value for reference types.",
	}
    
    // This part is tricky without access to the document content easily here
    // For now, let's return a generic message or specific if the client somehow sends the word (it doesn't)
    // A proper implementation would need to get the word at the hover position from the document text.
    // The TypeScript version did this:
    // const doc = documents.get(params.textDocument.uri); if (!doc) return null; ... const word = ...
    // We don't have easy access to the document content in this handler without more infrastructure
    // or passing it around, which `golang.org/x/tools/gopls/lsp/protocol` doesn't do by default for Hover.
    // The server is expected to fetch it from its document cache.

    // Let's assume we have the word for demonstration.
    // In a real scenario, you'd get the word from `params.Position` and the document content.
    // For now, we'll just show a generic hover.
    // To make this slightly more useful, we'd need to read the document:
    s.mu.Lock()
    docState, ok := s.documents[params.TextDocument.URI]
    s.mu.Unlock()

    var word = ""
    if ok {
        // Extremely naive way to get a word at position for demonstration
        // A real implementation would use a proper tokenizer or AST traversal
        lines := strings.Split(docState.content, "\n")
        if int(params.Position.Line) < len(lines) {
            line := lines[int(params.Position.Line)]
            // This is not robust:
            wordsOnLine := strings.FieldsFunc(line, func(r rune) bool {
				return !strings.ContainsRune("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_", r)
			})
            // Find word at character pos (very rough)
            charCount := 0
            for _, w := range wordsOnLine {
                if charCount <= int(params.Position.Character) && int(params.Position.Character) < charCount+len(w) {
                    word = w
                    break
                }
                charCount += len(w) + 1 // +1 for space
            }
        }
    }


	if doc, ok := keywordDocs[word]; ok {
		return &protocol.Hover{
			Contents: protocol.MarkupContent{
				Kind:  protocol.MarkdownMarkup,
				Value: "**" + word + "** (Manuscript Keyword)\n\n" + doc,
			},
		}, nil
	}

	return &protocol.Hover{
		Contents: protocol.MarkupContent{
			Kind:  protocol.MarkdownMarkup,
			Value: "Manuscript Hover (Go LSP)\n\nToken: `" + word + "`\n\nMore information requires integration with Manuscript's internal analysis tools.",
		},
	}, nil
}

// FoldingRange Handler (New)
func (s *manuscriptServer) FoldingRange(ctx context.Context, params *protocol.FoldingRangeTextDocumentParams) ([]protocol.FoldingRange, error) {
	docURI := params.TextDocument.URI
	log.Printf("Server: FoldingRange requested for %s\n", docURI)

	s.mu.Lock()
	doc, ok := s.documents[docURI]
	s.mu.Unlock()

	if !ok {
		return nil, jsonrpc2.NewError(jsonrpc2.InternalError, "document not found for folding ranges")
	}

	lines := strings.Split(doc.content, "\n")
	ranges := []protocol.FoldingRange{}
	stack := []int{} // Store starting line numbers of blocks

	// Region and comment folding
	regionStack := []int{}
	commentRegionStack := []int{}

	for i, line := range lines {
		trimmedLine := strings.TrimSpace(line)

		// Region folding (e.g., // {region ... // }endregion)
		if strings.HasPrefix(trimmedLine, "//{region") || strings.HasPrefix(trimmedLine, "// #region") {
			regionStack = append(regionStack, i)
		} else if strings.HasPrefix(trimmedLine, "//}endregion") || strings.HasPrefix(trimmedLine, "// #endregion") {
			if len(regionStack) > 0 {
				startLine := regionStack[len(regionStack)-1]
				regionStack = regionStack[:len(regionStack)-1]
				if i > startLine {
					ranges = append(ranges, protocol.FoldingRange{
						StartLine: uint32(startLine),
						EndLine:   uint32(i),
						Kind:      protocol.RegionFoldingRange,
					})
				}
			}
		}

		// Basic block comment folding /* ... */
        // This simple version assumes block comments start and end on different lines mostly
		if strings.Contains(trimmedLine, "/*") && !strings.Contains(trimmedLine, "*/") {
			commentRegionStack = append(commentRegionStack, i)
		}
		if strings.Contains(trimmedLine, "*/") && !strings.Contains(trimmedLine, "/*") {
			if len(commentRegionStack) > 0 {
				startLine := commentRegionStack[len(commentRegionStack)-1]
				commentRegionStack = commentRegionStack[:len(commentRegionStack)-1]
                 if i > startLine {
					ranges = append(ranges, protocol.FoldingRange{
						StartLine: uint32(startLine),
						EndLine:   uint32(i),
						Kind:      protocol.CommentFoldingRange,
					})
				}
            }
		}


		// Brace folding (simple, based on lines containing braces)
		if strings.Contains(line, "{") {
			stack = append(stack, i)
		}
		if strings.Contains(line, "}") {
			if len(stack) > 0 {
				startLine := stack[len(stack)-1]
				stack = stack[:len(stack)-1]
				// Ensure the end line is after the start line for a valid multi-line fold
				if i > startLine {
					ranges = append(ranges, protocol.FoldingRange{
						StartLine: uint32(startLine),
						EndLine:   uint32(i),
						Kind:      protocol.RegionFoldingRange, // Default kind
					})
				}
			}
		}
	}
	return ranges, nil
}


func main() {
	log.SetOutput(os.Stderr)
	log.Println("Manuscript Language Server (Go) starting with enhanced features...")

	ctx := context.Background()
	stream := jsonrpc2.NewHeaderStream(os.Stdin, os.Stdout)
	jsonrpcConn := jsonrpc2.NewConn(stream)
	serverHandler := newManuscriptServer(nil)
	lspServer := protocol.NewServer(jsonrpcConn, serverHandler)
	serverHandler.conn = lspServer // Important: give handler a way to send notifications

	if err := lspServer.Run(ctx); err != nil {
		log.Fatalf("LSP server failed: %v\n", err)
	}
	log.Println("Manuscript Language Server (Go) stopped.")
}
