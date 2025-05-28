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
	"manuscript-lang/manuscript/internal/sourcemap"
	"manuscript-lang/manuscript/internal/visitors/go-transpiler"
	mastb "manuscript-lang/manuscript/internal/visitors/mast-builder"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/antlr4-go/antlr/v4"
)

type CompileResult struct {
	GoCode    string
	SourceMap *sourcemap.SourceMap
	Error     error
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
	result := compileFile(filename, cfg, false)
	if result.Error != nil {
		fmt.Printf("Error compiling Manuscript: %v\n", result.Error)
		return
	}

	tmpFile, err := os.CreateTemp("", "manuscript_run_*.go")
	if err != nil {
		fmt.Printf("Error creating temporary file: %v\n", err)
		return
	}
	defer os.Remove(tmpFile.Name())

	if _, err := tmpFile.WriteString(result.GoCode); err != nil {
		fmt.Printf("Error writing to temporary file: %v\n", err)
		tmpFile.Close()
		return
	}
	tmpFile.Close()

	cmd := exec.Command("go", "run", tmpFile.Name())
	cmd.Stdout = os.Stdout

	var stderrBuf bytes.Buffer
	cmd.Stderr = &stderrBuf

	err = cmd.Run()
	stderrOutput := stderrBuf.String()

	if stderrOutput != "" {
		if err != nil && result.SourceMap != nil {
			mapAndDisplayGoErrors(stderrOutput, result.SourceMap)
		} else if err != nil {
			fmt.Fprintf(os.Stderr, "Compilation errors:\n%s", stderrOutput)
		} else {
			fmt.Fprint(os.Stderr, stderrOutput)
		}
	} else if err != nil {
		fmt.Fprintf(os.Stderr, "Manuscript execution finished with error: %v\n", err)
	}
}

// BuildFile compiles a manuscript file and outputs Go code
func BuildFile(filename string, cfg *config.MsConfig, debug bool) {
	result := compileFile(filename, cfg, debug)
	if result.Error != nil {
		fmt.Printf("Error: %v\n", result.Error)
		return
	}
	fmt.Print(result.GoCode)

	if cfg.CompilerOptions.Sourcemap && result.SourceMap != nil && cfg.CompilerOptions.OutputDir != "" {
		baseName := strings.TrimSuffix(filepath.Base(filename), filepath.Ext(filepath.Base(filename)))
		sourcemapFile := filepath.Join(cfg.CompilerOptions.OutputDir, baseName+".go.map")
		if err := result.SourceMap.WriteToFile(sourcemapFile); err != nil {
			fmt.Fprintf(os.Stderr, "Warning: Failed to write sourcemap: %v\n", err)
		}
	}
}

// compileFile is the core compilation function
func compileFile(filename string, cfg *config.MsConfig, debug bool) CompileResult {
	sourceFile := filename
	if sourceFile == "" {
		sourceFile = cfg.CompilerOptions.EntryFile
	}
	if sourceFile == "" {
		return CompileResult{Error: errors.New("no source file specified")}
	}

	ctx, err := config.NewCompilerContext(cfg, filepath.Dir(sourceFile), sourceFile)
	if err != nil {
		return CompileResult{Error: err}
	}
	ctx.Debug = debug

	content, err := ctx.ModuleResolver.ResolveModule(ctx.SourceFile)
	if err != nil {
		return CompileResult{Error: fmt.Errorf("failed to read file %s: %v", ctx.SourceFile, err)}
	}

	goCode, sourceMap, err := manuscriptToGo(string(content), ctx)
	if err != nil {
		return CompileResult{Error: fmt.Errorf("failed to compile program: %v", err)}
	}

	return CompileResult{GoCode: goCode, SourceMap: sourceMap}
}

// CompileManuscriptFromString compiles manuscript code from a string
func CompileManuscriptFromString(msCode string, ctx *config.CompilerContext) (string, error) {
	goCode, _, err := manuscriptToGo(msCode, ctx)
	return goCode, err
}

func manuscriptToGo(input string, ctx *config.CompilerContext) (string, *sourcemap.SourceMap, error) {
	inputStream := antlr.NewInputStream(input)
	lexer := parser.NewManuscriptLexer(inputStream)
	stream := antlr.NewCommonTokenStream(lexer, antlr.TokenDefaultChannel)
	p := parser.NewManuscript(stream)
	p.GetInterpreter().SetPredictionMode(antlr.PredictionModeSLL)

	if ctx.Debug {
		dumpTokens(stream)
	}

	errorListener := NewSyntaxErrorListener()
	p.RemoveErrorListeners()
	p.AddErrorListener(errorListener)

	tree := p.Program()
	if len(errorListener.Errors) > 0 {
		for _, err := range errorListener.Errors {
			fmt.Printf("Syntax error: %s\n", err)
		}
		return "", nil, errors.New(SyntaxErrorCode)
	}

	visitor := mastb.NewParseTreeToAST()
	result := tree.Accept(visitor)

	mnode, ok := result.(*mast.Program)
	if !ok {
		return "", nil, fmt.Errorf("failed to convert parse tree to AST")
	}

	var goTranspiler *transpiler.GoTranspiler
	var sourcemapBuilder *sourcemap.Builder

	if ctx.Config.CompilerOptions.Sourcemap && ctx.SourceFile != "" {
		sourcemapBuilder = sourcemap.NewBuilder(ctx.SourceFile, "generated.go")
		goTranspiler = transpiler.NewGoTranspilerWithSourceMap("main", sourcemapBuilder)
	} else {
		goTranspiler = transpiler.NewGoTranspiler("main")
	}

	visitedNode := goTranspiler.Visit(mnode)
	if visitedNode == nil {
		return "", nil, fmt.Errorf("failed to transpile AST")
	}

	goAST, ok := visitedNode.(*ast.File)
	if !ok || goAST == nil {
		return "", nil, fmt.Errorf("transpiler did not return a valid Go file")
	}

	var buf bytes.Buffer
	config := printer.Config{Mode: printer.UseSpaces, Tabwidth: 4}
	if err := config.Fprint(&buf, token.NewFileSet(), goAST); err != nil {
		return "", nil, fmt.Errorf("failed to print Go AST: %v", err)
	}

	goCode := strings.TrimSpace(buf.String())
	var sourceMap *sourcemap.SourceMap

	if sourcemapBuilder != nil {
		sourceMap = sourcemapBuilder.Build()
		goCode += "\n" + sourcemap.GetSourceMapComment(ctx.SourceFile+".map")
	}

	return goCode, sourceMap, nil
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

func mapAndDisplayGoErrors(goErrorOutput string, sourceMap *sourcemap.SourceMap) {
	for _, line := range strings.Split(strings.TrimSpace(goErrorOutput), "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}

		_, goLine, goColumn, message, err := sourcemap.ParseGoError(line)
		if err != nil {
			fmt.Fprintf(os.Stderr, "%s\n", line)
			continue
		}

		msFile, msLine, msColumn, err := sourceMap.MapGoErrorToManuscript(goLine, goColumn)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error in generated Go code (line %d:%d): %s\n", goLine, goColumn, message)
			continue
		}

		printManuscriptError(msFile, msLine, msColumn, message)
	}
}

func printManuscriptError(file string, line, column int, message string) {
	data, err := os.ReadFile(file)
	if err != nil {
		fmt.Fprintf(os.Stderr, "%s:%d:%d: %s\n", file, line, column, message)
		return
	}

	lines := strings.Split(string(data), "\n")
	if line-1 < 0 || line-1 >= len(lines) {
		fmt.Fprintf(os.Stderr, "%s:%d:%d: %s\n", file, line, column, message)
		return
	}

	codeLine := lines[line-1]
	arrowColumn := column - 1
	if arrowColumn < 0 {
		arrowColumn = 0
	}
	arrow := strings.Repeat(" ", arrowColumn) + "^"

	fmt.Fprintf(os.Stderr, "\nError in %s at line %d, column %d:\n%s\n%s\n%s\n\n",
		file, line, column, codeLine, arrow, message)
}
