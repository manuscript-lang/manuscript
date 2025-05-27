package compile

import (
	"bytes"
	"errors"
	"fmt"
	"go/ast"
	"go/printer"
	"go/token"
	"log"
	mast "manuscript-lang/manuscript/internal/ast"
	"manuscript-lang/manuscript/internal/config"
	"manuscript-lang/manuscript/internal/parser"
	"manuscript-lang/manuscript/internal/visitors/go-transpiler"
	mastb "manuscript-lang/manuscript/internal/visitors/mast-builder"
	"path/filepath"
	"strings"

	"github.com/antlr4-go/antlr/v4"
)

type CompileResult struct {
	GoCode string
	Error  error
}

const SyntaxErrorCode = "// SYNTAX ERROR"

type SyntaxErrorListener struct {
	*antlr.DefaultErrorListener
	Errors []string
}

func NewSyntaxErrorListener() *SyntaxErrorListener {
	return &SyntaxErrorListener{Errors: make([]string, 0)}
}

func (l *SyntaxErrorListener) SyntaxError(
	recognizer antlr.Recognizer,
	offendingSymbol interface{},
	line, column int,
	msg string,
	e antlr.RecognitionException,
) {
	l.Errors = append(l.Errors, fmt.Sprintf("line %d:%d %s", line, column, msg))
}

// RunFile compiles and runs a manuscript file
func RunFile(filename string, cfg *config.MsConfig) {
	ctx, err := createCompilerContext(filename, cfg, false)
	if err != nil {
		fmt.Printf("Error: %v\n", err)
		return
	}

	result := CompileManuscript(ctx)
	if result.Error != nil {
		fmt.Printf("Error: %v\n", result.Error)
		return
	}
	fmt.Print(result.GoCode)
}

// BuildFile compiles a manuscript file for building
func BuildFile(filename string, cfg *config.MsConfig, debug bool) {
	ctx, err := createCompilerContext(filename, cfg, debug)
	if err != nil {
		fmt.Printf("Error: %v\n", err)
		return
	}

	result := CompileManuscript(ctx)
	if result.Error != nil {
		fmt.Printf("Error: %v\n", result.Error)
		return
	}
	fmt.Print(result.GoCode)
}

func CompileManuscript(ctx *config.CompilerContext) CompileResult {
	content, err := ctx.ModuleResolver.ResolveModule(ctx.SourceFile)
	if err != nil {
		return CompileResult{Error: fmt.Errorf("failed to read file %s: %v", ctx.SourceFile, err)}
	}

	goCode, err := manuscriptToGo(string(content), ctx)
	if err != nil {
		return CompileResult{Error: fmt.Errorf("failed to compile program: %v", err)}
	}

	return CompileResult{GoCode: goCode}
}

func CompileManuscriptFromString(msCode string, ctx *config.CompilerContext) (string, error) {
	return manuscriptToGo(msCode, ctx)
}

// createCompilerContext creates a context with the provided config
func createCompilerContext(filename string, cfg *config.MsConfig, debug bool) (*config.CompilerContext, error) {
	sourceFile := filename
	if sourceFile == "" && cfg.CompilerOptions.EntryFile != "" {
		sourceFile = cfg.CompilerOptions.EntryFile
	}

	if sourceFile == "" {
		return nil, errors.New("no source file specified")
	}

	workingDir := filepath.Dir(sourceFile)

	ctx, err := config.NewCompilerContext(cfg, workingDir, sourceFile)
	if err != nil {
		return nil, err
	}

	if debug {
		ctx.Debug = true
	}

	return ctx, nil
}

func manuscriptToGo(input string, ctx *config.CompilerContext) (string, error) {
	tree, errorListener := parseManuscriptCode(input, ctx.Debug)
	if len(errorListener.Errors) > 0 {
		for _, err := range errorListener.Errors {
			fmt.Printf("Syntax error: %s\n", err)
		}
		return "", errors.New(SyntaxErrorCode)
	}

	return convertToGoCode(tree), nil
}

func parseManuscriptCode(msCode string, debug bool) (parser.IProgramContext, *SyntaxErrorListener) {
	inputStream := antlr.NewInputStream(msCode)
	lexer := parser.NewManuscriptLexer(inputStream)
	stream := antlr.NewCommonTokenStream(lexer, antlr.TokenDefaultChannel)
	p := parser.NewManuscript(stream)
	p.GetInterpreter().SetPredictionMode(antlr.PredictionModeSLL)

	if debug {
		dumpTokens(stream)
	}

	errorListener := NewSyntaxErrorListener()
	p.RemoveErrorListeners()
	p.AddErrorListener(errorListener)

	return p.Program(), errorListener
}

func convertToGoCode(tree parser.IProgramContext) string {
	visitor := mastb.NewParseTreeToAST()
	result := tree.Accept(visitor)

	mnode, ok := result.(*mast.Program)
	if !ok {
		return ""
	}

	transpiler := transpiler.NewGoTranspiler("main")
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
	stream.Seek(0)
}
