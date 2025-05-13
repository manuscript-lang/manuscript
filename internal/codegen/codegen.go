package codegen

import (
	"bytes"
	"fmt"
	"go/ast"
	"go/printer"
	"go/token"
	"log"
	"manuscript-co/manuscript/internal/parser"

	"github.com/antlr4-go/antlr/v4"
)

// CodeGenerator is responsible for generating Go code from the parsed AST.
type CodeGenerator struct{}

// NewCodeGenerator creates a new instance of CodeGenerator.
func NewCodeGenerator() *CodeGenerator {
	return &CodeGenerator{}
}

// Generate takes the parsed Manuscript AST root and produces Go code using the visitor.
func (cg *CodeGenerator) Generate(astNode interface{}) (string, error) {
	root, ok := astNode.(antlr.ParseTree)
	if !ok {
		// Use fmt.Errorf for error creation
		return "", fmt.Errorf("error: Input to Generate is not an antlr.ParseTree")
	}

	visitor := NewGoAstVisitor()
	// The top-level visit should return the complete Go AST File node.
	// The Visit method starts the traversal. It will dispatch to VisitProgram.
	visitedNode := visitor.Visit(root)

	// Check if the result is the expected *ast.File
	goAST, ok := visitedNode.(*ast.File)
	if !ok || goAST == nil {
		// Log the type returned if it wasn't *ast.File
		log.Printf("Error: Visiting the root node did not return a valid *ast.File. Got type: %T", visitedNode)
		return "", fmt.Errorf("error: AST generation failed to produce a Go file node")
	}

	fileSet := token.NewFileSet() // Need fileset for printing
	var buf bytes.Buffer
	config := printer.Config{Mode: printer.TabIndent | printer.UseSpaces, Tabwidth: 4}
	// Print the generated Go AST to the buffer
	if err := config.Fprint(&buf, fileSet, goAST); err != nil {
		return "", fmt.Errorf("error printing Go AST: %w", err)
	}
	return buf.String(), nil
}

// VisitLetDecl handles variable declarations like "let x = 10;"
func (v *ManuscriptAstVisitor) VisitLetDecl(ctx *parser.LetDeclContext) interface{} {
	log.Printf("VisitLetDecl: Called for '%s'", ctx.GetText())

	// Go statement to return eventually
	var declStmt ast.Stmt

	// For multiple assignments in a single let declaration, we'll create a block statement
	if len(ctx.GetAssignments()) > 1 {
		blockStmt := &ast.BlockStmt{List: []ast.Stmt{}}

		for _, assignment := range ctx.GetAssignments() {
			if assignmentResult := v.VisitLetAssignment(assignment.(*parser.LetAssignmentContext)); assignmentResult != nil {
				if assignStmt, ok := assignmentResult.(ast.Stmt); ok {
					blockStmt.List = append(blockStmt.List, assignStmt)
				} else {
					log.Printf("VisitLetDecl: Assignment result is not a statement: %T", assignmentResult)
				}
			}
		}

		declStmt = blockStmt
	} else if len(ctx.GetAssignments()) == 1 {
		// For a single assignment, just return the statement
		assignment := ctx.GetAssignments()[0]
		assignmentResult := v.VisitLetAssignment(assignment.(*parser.LetAssignmentContext))
		if stmt, ok := assignmentResult.(ast.Stmt); ok {
			declStmt = stmt
		} else {
			log.Printf("VisitLetDecl: Single assignment result is not a statement: %T", assignmentResult)
		}
	} else {
		log.Printf("VisitLetDecl: No assignments found in let declaration")
		return nil
	}

	return declStmt
}
