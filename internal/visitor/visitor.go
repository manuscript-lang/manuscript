package visitor

import (
	"go/ast"
	gotoken "go/token" // Aliased to avoid conflict
	"manuscript-co/manuscript/internal/parser"

	"github.com/antlr4-go/antlr/v4"
)

type ManuscriptAstVisitor struct {
	*parser.BaseManuscriptVisitor
	ProgramImports map[string]bool
	Errors         []CompilationError // Assuming CompilationError is defined elsewhere or NewCompilationError handles it
	loopDepth      int
	fileSet        *gotoken.FileSet // Corrected to use aliased package
}

// Reverted to use NewCompilationError, assuming it's correctly defined in the package.
func (v *ManuscriptAstVisitor) addError(message string, token antlr.Token) {
	v.Errors = append(v.Errors, NewCompilationError(message, token))
}

func NewManuscriptAstVisitor() *ManuscriptAstVisitor {
	return &ManuscriptAstVisitor{
		BaseManuscriptVisitor: &parser.BaseManuscriptVisitor{},
		ProgramImports:        make(map[string]bool),
		Errors:                make([]CompilationError, 0),
		loopDepth:             0,
		fileSet:               gotoken.NewFileSet(), // Corrected to use aliased package
	}
}

var _ parser.ManuscriptVisitor = (*ManuscriptAstVisitor)(nil)

func (v *ManuscriptAstVisitor) VisitChildren(node antlr.RuleNode) interface{} {
	var result interface{}
	for i := 0; i < node.GetChildCount(); i++ {
		child := node.GetChild(i)
		if pt, ok := child.(antlr.ParseTree); ok {
			childResult := pt.Accept(v)
			if childResult != nil {
				result = childResult
			}
		}
	}
	return result
}

func (v *ManuscriptAstVisitor) Visit(tree antlr.ParseTree) interface{} {
	if tree == nil {
		v.addError("Attempted to visit a nil tree node", nil)
		return &ast.BadStmt{From: gotoken.NoPos, To: gotoken.NoPos} // Corrected to use aliased package
	}
	return tree.Accept(v)
}

func (v *ManuscriptAstVisitor) VisitErrorNode(node antlr.ErrorNode) interface{} {
	v.addError("Error node encountered: "+node.GetText(), node.GetSymbol())
	return &ast.BadStmt{From: v.pos(node.GetSymbol()), To: v.pos(node.GetSymbol())}
}

// Corrected pos function to use aliased gotoken
func (v *ManuscriptAstVisitor) pos(token antlr.Token) gotoken.Pos {
	if token == nil {
		return gotoken.NoPos
	}
	// Placeholder - actual position mapping is more involved
	return gotoken.NoPos
}

// --- Loop and Control Flow Statements ---
// These methods (VisitForStmt, VisitForInitPattn, VisitWhileStmt, VisitBreakStmt, VisitContinueStmt)
// have been moved to statements.go as they were causing redeclaration errors.
// Their presence here was from a previous editing step.

// Removed the local CompilationError struct definition as it was causing redeclaration errors
// and is assumed to be defined elsewhere in the package or handled by NewCompilationError.

// func NewCompilationError(message string, token antlr.Token) CompilationError { ... }
// func (e CompilationError) String() string { ... }
// These should be defined once, typically where CompilationError struct is defined.
