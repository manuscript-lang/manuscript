package visitor

import (
	"manuscript-co/manuscript/internal/parser"

	"github.com/antlr4-go/antlr/v4"
)

type ManuscriptAstVisitor struct {
	*parser.BaseManuscriptVisitor
	ProgramImports map[string]bool
	Errors         []CompilationError
}

func (v *ManuscriptAstVisitor) addError(message string, token antlr.Token) {
	v.Errors = append(v.Errors, NewCompilationError(message, token))
}

func NewManuscriptAstVisitor() *ManuscriptAstVisitor {
	return &ManuscriptAstVisitor{
		BaseManuscriptVisitor: &parser.BaseManuscriptVisitor{},
		ProgramImports:        make(map[string]bool),
		Errors:                make([]CompilationError, 0),
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

func (v *ManuscriptAstVisitor) VisitErrorNode(node antlr.ErrorNode) interface{} {
	v.addError("Error node encountered: "+node.GetText(), node.GetSymbol())
	return nil
}
