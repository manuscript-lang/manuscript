package main

import (
	"fmt"
	"manuscript-co/manuscript/tests/minimal/parser"

	"github.com/antlr4-go/antlr/v4"
)

func main() {
	lexer := parser.NewToyLexer(antlr.NewInputStream("let x = a"))
	stream := antlr.NewCommonTokenStream(lexer, antlr.TokenDefaultChannel)
	p := parser.NewToy(stream)
	p.AddErrorListener(antlr.NewDiagnosticErrorListener(true))
	tree := p.Program()
	visitor := &ToyVisitor{}
	visitor.Visit(tree)
}

type ToyVisitor struct {
	parser.BaseToyVisitor
}

func (v *ToyVisitor) VisitProgram(ctx *parser.ProgramContext) interface{} {
	fmt.Println("VisitProgram")
	v.VisitChildren(ctx)
	return nil
}

func (v *ToyVisitor) VisitProgramItem(ctx *parser.ProgramItemContext) interface{} {
	fmt.Println("VisitProgramItem")
	// v.VisitChildren(ctx)
	return nil
}

func (v *ToyVisitor) VisitLet(ctx *parser.LetContext) interface{} {
	fmt.Println("VisitLet")
	v.VisitChildren(ctx)
	return nil
}

func (v *ToyVisitor) VisitFn(ctx *parser.FnContext) interface{} {
	fmt.Println("VisitFn")
	v.VisitChildren(ctx)
	return nil
}

func (v *ToyVisitor) VisitExpr(ctx *parser.ExprContext) interface{} {
	fmt.Println("VisitExpr")
	v.VisitChildren(ctx)
	return nil
}

func (v *ToyVisitor) VisitLetLabel(ctx *parser.LetLabelContext) interface{} {
	fmt.Println("VisitLetLabel")
	v.VisitChildren(ctx)
	return nil
}

func (v *ToyVisitor) VisitFnLabel(ctx *parser.FnLabelContext) interface{} {
	fmt.Println("VisitFnLabel")
	v.VisitChildren(ctx)
	return nil
}

// General Visit methods (delegation and error handling)
// VisitChildren visits the children of a node.
// It returns the result of visiting the last child, or nil if no children produce a result.
func (v *ToyVisitor) VisitChildren(node antlr.RuleNode) interface{} {
	var result interface{}
	for _, child := range node.GetRuleContext().GetChildren() {
		if child == nil {
			continue
		}
		if pt, ok := child.(antlr.ParseTree); ok {
			childResult := v.Visit(pt)
			if childResult != nil {
				result = childResult // Keep the last non-nil result
			}
		}
	}
	return result
}

func (v *ToyVisitor) Visit(tree antlr.ParseTree) interface{} {
	return tree.Accept(v)
}
