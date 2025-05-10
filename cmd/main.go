package main

import (
	"fmt"
	"manuscript-co/manuscript/internal/parser"
	"strconv"

	"github.com/antlr4-go/antlr/v4"
)

// Calculator implements the ManuscriptListener interface
type Calculator struct {
	parser.BaseManuscriptListener
	stack []int
}

// Push value onto the stack
func (c *Calculator) push(i int) {
	c.stack = append(c.stack, i)
}

// Pop value from the stack
func (c *Calculator) pop() int {
	if len(c.stack) < 1 {
		panic("Stack is empty")
	}
	result := c.stack[len(c.stack)-1]
	c.stack = c.stack[:len(c.stack)-1]
	return result
}

// ExitInt is called when exiting the Int production.
func (c *Calculator) ExitInt(ctx *parser.IntContext) {
	value, _ := strconv.Atoi(ctx.GetText())
	c.push(value)
}

// ExitAddSub is called when exiting the AddSub production.
func (c *Calculator) ExitAddSub(ctx *parser.AddSubContext) {
	right := c.pop()
	left := c.pop()

	if ctx.ADD() != nil {
		c.push(left + right)
	} else {
		c.push(left - right)
	}
}

// ExitMulDiv is called when exiting the MulDiv production.
func (c *Calculator) ExitMulDiv(ctx *parser.MulDivContext) {
	right := c.pop()
	left := c.pop()

	if ctx.MUL() != nil {
		c.push(left * right)
	} else {
		c.push(left / right)
	}
}

// ExitParens is called when exiting the Parens production.
func (c *Calculator) ExitParens(ctx *parser.ParensContext) {
	// The value is already on the stack
}

func ExecuteProgram(program string) (string, error) {
	inputStream := antlr.NewInputStream(program)

	// Create lexer
	lexer := parser.NewManuscriptLexer(inputStream)
	tokenStream := antlr.NewCommonTokenStream(lexer, antlr.TokenDefaultChannel)

	// Create parser
	p := parser.NewManuscriptParser(tokenStream)

	// Create custom listener
	calculator := &Calculator{}

	// Parse input
	tree := p.Program()
	antlr.ParseTreeWalkerDefault.Walk(calculator, tree)

	// Get result
	result := calculator.pop()
	return fmt.Sprint(result), nil
}

func main() {
	fmt.Println("Manuscript ANTLR parser demo")
	// Create input for parsing
	input := "2 * (3 + 4);"
	result, _ := ExecuteProgram(input)
	fmt.Printf("Expression '%s' evaluates to %s\n", input, result)
	fmt.Println("Expression parsed successfully")
}
