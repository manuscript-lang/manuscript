package visitor

import (
	"manuscript-co/manuscript/internal/parser"

	"github.com/antlr4-go/antlr/v4"
)

// ManuscriptAstVisitor implements the ANTLR visitor pattern to build a Go AST.
// It embeds the base visitor struct provided by ANTLR.
type ManuscriptAstVisitor struct {
	*parser.BaseManuscriptVisitor
	// Add any necessary state fields here if needed (e.g., symbol table)
	ProgramImports map[string]bool // Added to store program imports
}

// NewGoAstVisitor creates a new visitor instance.
func NewGoAstVisitor() *ManuscriptAstVisitor {
	// Initialize with the base visitor. It's important to initialize the embedded struct.
	return &ManuscriptAstVisitor{
		BaseManuscriptVisitor: &parser.BaseManuscriptVisitor{},
		ProgramImports:        make(map[string]bool), // Initialize the map
	}
}

var _ parser.ManuscriptVisitor = (*ManuscriptAstVisitor)(nil) // Static check: verify ManuscriptAstVisitor implements ManuscriptVisitor

// --- Visitor Method Implementations (Starting Point) ---

// VisitChildren implements the default behavior of visiting children nodes.
// ANTLR's Go target requires this to be implemented manually for traversal.
func (v *ManuscriptAstVisitor) VisitChildren(node antlr.RuleNode) interface{} {
	var result interface{}
	for i := 0; i < node.GetChildCount(); i++ {
		child := node.GetChild(i)
		// Ensure the child is a ParseTree before calling Accept
		if pt, ok := child.(antlr.ParseTree); ok {
			result = pt.Accept(v)
			// TODO: Decide if we need to aggregate results or handle specific return values.
			// For now, just continue traversal. If a Visit* method returns something
			// specific (like an error or a specific AST node), we might need logic here.
		}
	}
	return result // Often nil in visitor patterns where side effects dominate.
}

// Visit implements parser.ManuscriptVisitor.
func (v *ManuscriptAstVisitor) Visit(tree antlr.ParseTree) interface{} {
	// The default Visit method provided by ANTLR often delegates to Accept.
	// We can keep the default or customize if needed. Usually, Accept is preferred.
	// For safety, let's ensure Accept is called.
	if tree == nil {
		return nil
	}
	return tree.Accept(v)
}

// VisitTerminal is called for leaf nodes (tokens). Usually ignored unless needed.
// func (v *GoAstVisitor) VisitTerminal(node antlr.TerminalNode) interface{} {
// 	return nil // Or return node.GetText() if needed
// }

// VisitErrorNode is called if the parser encounters an error.
// func (v *GoAstVisitor) VisitErrorNode(node antlr.ErrorNode) interface{} {
// 	log.Printf("Error node encountered: %s", node.GetText())
// 	return nil // Or an error representation
// }
