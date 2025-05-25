package transpiler

import (
	"fmt"
	"go/ast"
	"go/token"
	"strings"

	msast "manuscript-co/manuscript/internal/ast"
)

// GoTranspiler converts Manuscript AST to Go AST
type GoTranspiler struct {
	// Configuration
	PackageName string
	Imports     []*ast.ImportSpec // import specifications

	// State management
	fileSet      *token.FileSet
	errors       []error
	tempVarCount int
	loopDepth    int

	// Current context
	currentFile  *ast.File
	currentDecls []ast.Decl

	// Optimizations
	stringConcat   bool // Enable efficient string concatenation
	sliceOptimized bool // Enable slice optimizations
	memOptimized   bool // Enable memory allocation optimizations
}

// PipelineBlockStmt represents a pipeline block that should not be flattened
// This preserves the block structure for pipeline statements in the generated Go code
type PipelineBlockStmt struct {
	*ast.BlockStmt
}

// DestructuringBlockStmt represents a destructuring block that should not be flattened
// This preserves the block structure for standalone destructuring statements in the generated Go code
type DestructuringBlockStmt struct {
	*ast.BlockStmt
}

// MultipleDeclarations represents multiple declarations that should be processed in order
// This is used for cases like destructured imports where one AST node generates multiple Go declarations
type MultipleDeclarations struct {
	Decls []ast.Decl
}

// Pos implements ast.Node interface
func (m *MultipleDeclarations) Pos() token.Pos {
	if len(m.Decls) > 0 {
		return m.Decls[0].Pos()
	}
	return token.NoPos
}

// End implements ast.Node interface
func (m *MultipleDeclarations) End() token.Pos {
	if len(m.Decls) > 0 {
		return m.Decls[len(m.Decls)-1].End()
	}
	return token.NoPos
}

// NewGoTranspiler creates a new transpiler instance
func NewGoTranspiler(packageName string) *GoTranspiler {
	return &GoTranspiler{
		PackageName:    packageName,
		Imports:        []*ast.ImportSpec{},
		fileSet:        token.NewFileSet(),
		errors:         []error{},
		stringConcat:   true,
		sliceOptimized: true,
		memOptimized:   true,
	}
}

// Visit implements the visitor pattern using the reusable dispatch function
func (t *GoTranspiler) Visit(node msast.Node) ast.Node {
	return msast.DispatchVisit(t, node)
}

// TranspileProgram transpiles a Manuscript program to Go AST
func (t *GoTranspiler) TranspileProgram(program *msast.Program) (*ast.File, error) {
	// Reset state
	t.errors = []error{}
	t.currentDecls = []ast.Decl{}

	// Visit the program
	result := t.Visit(program)

	if len(t.errors) > 0 {
		return nil, fmt.Errorf("transpilation errors: %v", t.errors)
	}

	// Return the generated file or create a basic one
	if file, ok := result.(*ast.File); ok {
		return file, nil
	}

	// Fallback: create a basic Go file structure
	goFile := &ast.File{
		Name:    &ast.Ident{Name: t.PackageName},
		Decls:   t.currentDecls,
		Package: token.NoPos,
	}

	return goFile, nil
}

// Error handling
func (t *GoTranspiler) addError(msg string, node msast.Node) {
	pos := ""
	if node != nil {
		pos = fmt.Sprintf(" at %s", node.Pos())
	}
	t.errors = append(t.errors, fmt.Errorf("%s%s", msg, pos))
}

// Utility methods
func (t *GoTranspiler) nextTempVar() string {
	t.tempVarCount++
	return fmt.Sprintf("__val%d", t.tempVarCount)
}

// Position utilities
func (t *GoTranspiler) pos(node msast.Node) token.Pos {
	if node == nil {
		return token.NoPos
	}
	// For now return NoPos, in a real implementation we'd map positions
	return token.NoPos
}

// Loop management
func (t *GoTranspiler) enterLoop() {
	t.loopDepth++
}

func (t *GoTranspiler) exitLoop() {
	if t.loopDepth > 0 {
		t.loopDepth--
	}
}

func (t *GoTranspiler) isInLoop() bool {
	return t.loopDepth > 0
}

// addErrorsImport adds the "errors" import if not already present
func (t *GoTranspiler) addErrorsImport() {
	// Check if errors import already exists
	for _, importSpec := range t.Imports {
		if importSpec.Path != nil && importSpec.Path.Value == `"errors"` {
			return // Already imported
		}
	}

	// Add errors import
	errorsImport := &ast.ImportSpec{
		Path: &ast.BasicLit{
			Kind:  token.STRING,
			Value: `"errors"`,
		},
	}
	t.Imports = append(t.Imports, errorsImport)
}

// Generate better variable names
func (t *GoTranspiler) generateVarName(base string) string {
	if base == "" {
		return t.nextTempVar()
	}

	// Clean up the base name to be Go-compliant
	cleaned := strings.Map(func(r rune) rune {
		if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') || r == '_' {
			return r
		}
		return '_'
	}, base)

	if cleaned == "" || (cleaned[0] >= '0' && cleaned[0] <= '9') {
		cleaned = "_" + cleaned
	}

	return cleaned
}

// String concatenation optimization
func (t *GoTranspiler) optimizeStringConcat(left, right ast.Expr) ast.Expr {
	if !t.stringConcat {
		return &ast.BinaryExpr{
			X:  left,
			Op: token.ADD,
			Y:  right,
		}
	}

	// Use strings.Builder for multiple concatenations
	// For now, just return simple concatenation
	return &ast.BinaryExpr{
		X:  left,
		Op: token.ADD,
		Y:  right,
	}
}

// Type conversion utilities
func (t *GoTranspiler) manuscriptTypeToGoType(msType msast.Type) ast.Expr {
	if msType == nil {
		return &ast.Ident{Name: "interface{}"}
	}

	// This would need to be implemented based on the Manuscript type system
	// For now, return a placeholder
	return &ast.Ident{Name: "interface{}"}
}

// Helper to convert expressions to statements
func (t *GoTranspiler) exprToStmt(expr ast.Expr) ast.Stmt {
	if expr == nil {
		return nil
	}
	return &ast.ExprStmt{X: expr}
}

// Helper to convert manuscript identifier to Go identifier
func (t *GoTranspiler) convertIdentifier(name string) *ast.Ident {
	return &ast.Ident{Name: t.generateVarName(name)}
}
