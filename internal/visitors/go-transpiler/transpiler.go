package transpiler

import (
	"fmt"
	"go/ast"
	"go/token"
	"strings"

	mast "manuscript-lang/manuscript/internal/ast"
	"manuscript-lang/manuscript/internal/sourcemap"
)

// GoTranspiler converts Manuscript AST to Go AST
type GoTranspiler struct {
	// Configuration
	PackageName string
	Imports     []*ast.ImportSpec // import specifications

	// State management
	fileSet         *token.FileSet
	errors          []error
	tempVarCount    int
	loopDepth       int
	positionCounter int // Counter for generating unique positions

	// Current context
	currentFile      *ast.File
	currentDecls     []ast.Decl
	currentTokenFile *token.File

	// Sourcemap support
	sourcemapBuilder *sourcemap.Builder
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
		PackageName:     packageName,
		Imports:         []*ast.ImportSpec{},
		fileSet:         token.NewFileSet(),
		errors:          []error{},
		positionCounter: 1, // Start position counter at 1
	}
}

// NewGoTranspilerWithSourceMap creates a new transpiler instance with sourcemap support
func NewGoTranspilerWithSourceMap(packageName string, sourcemapBuilder *sourcemap.Builder) *GoTranspiler {
	transpiler := &GoTranspiler{
		PackageName:      packageName,
		Imports:          []*ast.ImportSpec{},
		fileSet:          sourcemapBuilder.GetFileSet(), // Use the sourcemap builder's file set
		errors:           []error{},
		positionCounter:  1, // Start position counter at 1
		sourcemapBuilder: sourcemapBuilder,
	}
	return transpiler
}

// NewGoTranspilerWithPostPrintSourceMap creates a new transpiler instance with post-print sourcemap support
func NewGoTranspilerWithPostPrintSourceMap(packageName string, sourcemapBuilder *sourcemap.Builder) *GoTranspiler {
	transpiler := &GoTranspiler{
		PackageName:      packageName,
		Imports:          []*ast.ImportSpec{},
		fileSet:          token.NewFileSet(),
		errors:           []error{},
		positionCounter:  1, // Start position counter at 1
		sourcemapBuilder: sourcemapBuilder,
	}
	return transpiler
}

// Visit implements the visitor pattern using the reusable dispatch function
func (t *GoTranspiler) Visit(node mast.Node) ast.Node {
	return mast.DispatchVisit(t, node)
}

// TranspileProgram transpiles a Manuscript program to Go AST
func (t *GoTranspiler) TranspileProgram(program *mast.Program) (*ast.File, error) {
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
func (t *GoTranspiler) addError(msg string, node mast.Node) {
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
func (t *GoTranspiler) pos(node mast.Node) token.Pos {
	if node == nil {
		return token.NoPos
	}
	return token.NoPos
}

// posWithName creates a position and adds a sourcemap entry with a name
func (t *GoTranspiler) posWithName(node mast.Node, name string) token.Pos {
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

// registerNodeMapping registers a mapping between Go and Manuscript AST nodes for post-print source mapping
func (t *GoTranspiler) registerNodeMapping(goNode ast.Node, msNode mast.Node) {
	if t.sourcemapBuilder != nil {
		t.sourcemapBuilder.RegisterNodeMapping(goNode, msNode)
	}
}
