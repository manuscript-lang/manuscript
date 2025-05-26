package main

import (
	"bytes"
	"errors"
	"flag"
	"fmt"
	"go/ast"
	"go/printer"
	"go/token"
	"log"
	"os"
	"path/filepath"
	"strings"

	"github.com/antlr4-go/antlr/v4"

	mast "manuscript-lang/manuscript/internal/ast"
	"manuscript-lang/manuscript/internal/config"
	parser "manuscript-lang/manuscript/internal/parser"
	transpiler "manuscript-lang/manuscript/internal/visitors/go-transpiler"
	mastb "manuscript-lang/manuscript/internal/visitors/mast-builder"
)

const (
	syntaxErrorCode = "// SYNTAX ERROR"
)

// SyntaxErrorListener captures syntax errors from the ANTLR parser.
type SyntaxErrorListener struct {
	*antlr.DefaultErrorListener
	Errors []string
}

// NewSyntaxErrorListener creates a new instance of SyntaxErrorListener.
func NewSyntaxErrorListener() *SyntaxErrorListener {
	return &SyntaxErrorListener{Errors: make([]string, 0)}
}

// SyntaxError is called by ANTLR when a syntax error is encountered.
func (l *SyntaxErrorListener) SyntaxError(recognizer antlr.Recognizer, offendingSymbol interface{}, line, column int, msg string, e antlr.RecognitionException) {
	l.Errors = append(l.Errors, fmt.Sprintf("line %d:%d %s", line, column, msg))
}

func manuscriptToGo(input string, ctx *config.CompilerContext) (string, error) {
	tree, errorListener := parseManuscriptCode(input, ctx.Config.Debug)
	if len(errorListener.Errors) > 0 {
		for _, err := range errorListener.Errors {
			fmt.Printf("Syntax error: %s\n", err)
		}
		return "", errors.New(syntaxErrorCode)
	}

	return convertToGoCode(tree, ctx), nil
}

func parseManuscriptCode(msCode string, debug bool) (parser.IProgramContext, *SyntaxErrorListener) {
	inputStream := antlr.NewInputStream(msCode)
	lexer := parser.NewManuscriptLexer(inputStream)
	stream := antlr.NewCommonTokenStream(lexer, antlr.TokenDefaultChannel)
	p := parser.NewManuscript(stream)
	if debug {
		dumpTokens(stream)
	}
	errorListener := NewSyntaxErrorListener()
	p.RemoveErrorListeners()
	p.AddErrorListener(errorListener)

	tree := p.Program()
	return tree, errorListener
}

func convertToGoCode(tree parser.IProgramContext, ctx *config.CompilerContext) string {
	visitor := mastb.NewParseTreeToAST()
	result := tree.Accept(visitor)

	mnode, ok := result.(*mast.Program)
	if !ok {
		return ""
	}

	transpiler := transpiler.NewGoTranspiler(ctx.Config.PackageName)
	goNode := transpiler.Visit(mnode)
	if goNode == nil {
		return ""
	}

	return printGoAst(goNode)
}

func printGoAst(visitedNode ast.Node) string {
	goAST, ok := visitedNode.(*ast.File)
	if !ok || goAST == nil {
		return ""
	}

	fileSet := token.NewFileSet()
	var buf bytes.Buffer
	config := printer.Config{Mode: printer.UseSpaces, Tabwidth: 4}
	if err := config.Fprint(&buf, fileSet, goAST); err != nil {
		return ""
	}

	return strings.TrimSpace(buf.String())
}

func dumpTokens(stream *antlr.CommonTokenStream) {
	log.Println("--- Lexer Token Dump Start ---")
	stream.Fill()
	for i, token := range stream.GetAllTokens() {
		log.Printf("Token %d: Type=%d, Text='%s', Line=%d, Col=%d",
			i, token.GetTokenType(), token.GetText(), token.GetLine(), token.GetColumn())
	}
	log.Println("--- Lexer Token Dump End ---")
	stream.Seek(0) // Reset stream for parser
}

func main() {
	// Define command line flags
	debugFlag := flag.Bool("debug", false, "Enable token dumping for debugging")
	configFlag := flag.String("config", "", "Path to configuration file (ms.yml)")
	outputFlag := flag.String("output", "", "Output directory")
	packageFlag := flag.String("package", "", "Package name for generated Go code")
	flag.BoolVar(debugFlag, "d", false, "Enable token dumping for debugging (shorthand)")
	flag.Parse()

	args := flag.Args()
	if len(args) < 1 {
		fmt.Println("Usage: msc [-debug] [-config path] [-output dir] [-package name] <filename>")
		return
	}

	filename := args[0]

	// Get working directory
	workingDir, err := os.Getwd()
	if err != nil {
		fmt.Printf("failed to get working directory: %v\n", err)
		return
	}

	// Create compiler context
	var ctx *config.CompilerContext
	if *configFlag != "" {
		cfg, err := config.LoadConfigFromPath(*configFlag)
		if err != nil {
			fmt.Printf("failed to load config file %s: %v\n", *configFlag, err)
			return
		}
		ctx = config.NewCompilerContextWithConfig(cfg, workingDir)
	} else {
		ctx, err = config.NewCompilerContext(workingDir)
		if err != nil {
			fmt.Printf("failed to create compiler context: %v\n", err)
			return
		}
	}

	// Set source file and load local config
	absFilename, err := filepath.Abs(filename)
	if err != nil {
		fmt.Printf("failed to get absolute path for %s: %v\n", filename, err)
		return
	}

	err = ctx.SetSourceFile(absFilename)
	if err != nil {
		fmt.Printf("failed to set source file: %v\n", err)
		return
	}

	// Override config with command line flags (highest precedence)
	if *debugFlag {
		ctx.Config.Debug = true
	}
	if *outputFlag != "" {
		ctx.Config.OutputDir = *outputFlag
	}
	if *packageFlag != "" {
		ctx.Config.PackageName = *packageFlag
	}

	// Validate configuration
	err = ctx.Config.Validate()
	if err != nil {
		fmt.Printf("invalid configuration: %v\n", err)
		return
	}

	content, err := os.ReadFile(filename)
	if err != nil {
		fmt.Printf("failed to read file %s: %v\n", filename, err)
		return
	}

	program := string(content)
	goCode, err := manuscriptToGo(program, ctx)
	if err != nil {
		fmt.Printf("failed to compile program: %v\n", err)
		return
	}
	fmt.Printf("%s", goCode)
}
