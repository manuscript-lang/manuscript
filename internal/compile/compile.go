package compile

import (
	"bytes"
	"encoding/json"
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
	"strconv"
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
	ctx, err := createCompilerContext(filename, cfg, false)
	if err != nil {
		fmt.Printf("Error creating compiler context: %v\n", err)
		return
	}

	result := CompileManuscript(ctx)

	// Create a temporary Go file
	tmpFile, err := os.CreateTemp("", "manuscript_run_*.go")
	if err != nil {
		fmt.Printf("Error creating temporary file: %v\n", err)
		return
	}
	if result.Error != nil {
		fmt.Printf("Error compiling Manuscript: %v\n", result.Error)
		tmpFile.Close()
		return
	}

	if _, err := tmpFile.WriteString(result.GoCode); err != nil {
		fmt.Printf("Error writing to temporary file: %v\n", err)
		tmpFile.Close()
		return
	}
	if err := tmpFile.Close(); err != nil {
		fmt.Printf("Error closing temporary file: %v\n", err)
		return
	}

	// Write sourcemap if available for error mapping
	var sourcemapFile string
	if result.SourceMap != nil {
		sourcemapFile = tmpFile.Name() + ".map"
		if err := result.SourceMap.WriteToFile(sourcemapFile); err != nil {
			// Continue without sourcemap if writing fails
			sourcemapFile = ""
		}
	}

	cmd := exec.Command("go", "run", "-json", tmpFile.Name())
	var stdoutBuf, stderrBuf bytes.Buffer
	cmd.Stdout = &stdoutBuf
	cmd.Stderr = &stderrBuf

	err = cmd.Run()
	combinedOutput := stdoutBuf.String() + stderrBuf.String()

	if combinedOutput != "" && sourcemapFile != "" {
		lines := strings.Split(combinedOutput, "\n")
		for _, line := range lines {
			trimmed := strings.TrimSpace(line)
			if trimmed == "" {
				continue
			}
			var jsonLine struct {
				Output string `json:"Output"`
			}
			if err := json.Unmarshal([]byte(trimmed), &jsonLine); err == nil && jsonLine.Output != "" {
				outputLines := strings.Split(jsonLine.Output, "\n")
				for _, outLine := range outputLines {
					outLine = strings.TrimSpace(outLine)
					if outLine == "" {
						continue
					}
					mapped, err := sourcemap.MapGoErrorString(outLine, sourcemapFile)
					if err == nil {
						// Parse mapped error: file:line:col: message
						parts := strings.SplitN(mapped, ":", 4)
						if len(parts) == 4 {
							file := parts[0]
							lineNum, _ := strconv.Atoi(parts[1])
							colNum, _ := strconv.Atoi(parts[2])
							msg := strings.TrimSpace(parts[3])
							PrintManuscriptErrorWithContext(file, lineNum, colNum, msg)
							continue
						}
					}
					// Fallback: print raw
					fmt.Fprintf(os.Stderr, "%s\n", outLine)
				}
				continue
			}
			// Not a JSON line, try to map directly
			mapped, err := sourcemap.MapGoErrorString(line, sourcemapFile)
			if err == nil {
				parts := strings.SplitN(mapped, ":", 4)
				if len(parts) == 4 {
					file := parts[0]
					lineNum, _ := strconv.Atoi(parts[1])
					colNum, _ := strconv.Atoi(parts[2])
					msg := strings.TrimSpace(parts[3])
					PrintManuscriptErrorWithContext(file, lineNum, colNum, msg)
					continue
				}
			}
			fmt.Fprintf(os.Stderr, "%s\n", line)
		}
	}
	if err != nil {
		fmt.Fprintf(os.Stderr, "Manuscript execution finished with error: %v\n", err)
		return
	}
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

// BuildFileWithSourceMap compiles a manuscript file and generates a sourcemap
func BuildFileWithSourceMap(filename string, cfg *config.MsConfig, debug bool, outputDir string) {
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

	// Write Go code
	fmt.Print(result.GoCode)

	// Write sourcemap if available
	if result.SourceMap != nil && outputDir != "" {
		baseName := filepath.Base(filename)
		baseName = strings.TrimSuffix(baseName, filepath.Ext(baseName))
		sourcemapFile := filepath.Join(outputDir, baseName+".go.map")

		if err := result.SourceMap.WriteToFile(sourcemapFile); err != nil {
			fmt.Fprintf(os.Stderr, "Warning: Failed to write sourcemap: %v\n", err)
		}
	}
}

func CompileManuscript(ctx *config.CompilerContext) CompileResult {
	content, err := ctx.ModuleResolver.ResolveModule(ctx.SourceFile)
	if err != nil {
		return CompileResult{Error: fmt.Errorf("failed to read file %s: %v", ctx.SourceFile, err)}
	}

	goCode, sourceMap, err := manuscriptToGoWithSourceMap(string(content), ctx)
	if err != nil {
		return CompileResult{Error: fmt.Errorf("failed to compile program: %v", err)}
	}

	return CompileResult{GoCode: goCode, SourceMap: sourceMap}
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
	goCode, _, err := manuscriptToGoWithSourceMap(input, ctx)
	return goCode, err
}

func manuscriptToGoWithSourceMap(input string, ctx *config.CompilerContext) (string, *sourcemap.SourceMap, error) {
	tree, errorListener := parseManuscriptCode(input, ctx.Debug)
	if len(errorListener.Errors) > 0 {
		for _, err := range errorListener.Errors {
			fmt.Printf("Syntax error: %s\n", err)
		}
		return "", nil, errors.New(SyntaxErrorCode)
	}

	return convertToGoCodeWithSourceMap(tree, ctx.SourceFile)
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
	goCode, _, _ := convertToGoCodeWithSourceMap(tree, "")
	return goCode
}

func convertToGoCodeWithSourceMap(tree parser.IProgramContext, sourceFile string) (string, *sourcemap.SourceMap, error) {
	visitor := mastb.NewParseTreeToAST()
	result := tree.Accept(visitor)

	mnode, ok := result.(*mast.Program)
	if !ok {
		return "", nil, fmt.Errorf("failed to convert parse tree to AST")
	}

	// Create sourcemap builder and shared file set
	var sourcemapBuilder *sourcemap.Builder
	var goTranspiler *transpiler.GoTranspiler

	if sourceFile != "" {
		sourcemapBuilder = sourcemap.NewBuilder(sourceFile, "generated.go")
		goTranspiler = transpiler.NewGoTranspilerWithSourceMap("main", sourcemapBuilder)
	} else {
		goTranspiler = transpiler.NewGoTranspiler("main")
	}

	visitedNode := goTranspiler.Visit(mnode)
	if visitedNode == nil {
		return "", nil, fmt.Errorf("failed to transpile AST")
	}

	// Print the Go AST and create source map
	if sourcemapBuilder != nil {
		goCode, sourceMap := printGoAstWithSourceMap(visitedNode, sourcemapBuilder, mnode, sourceFile)
		return goCode, sourceMap, nil
	} else {
		return printGoAst(visitedNode), nil, nil
	}
}

// printGoAstWithSourceMap prints the Go AST and returns the source map built during transpilation
func printGoAstWithSourceMap(visitedNode ast.Node, builder *sourcemap.Builder, mnode *mast.Program, sourceFile string) (string, *sourcemap.SourceMap) {
	goAST, ok := visitedNode.(*ast.File)
	if !ok || goAST == nil {
		return "", nil
	}

	// Print the AST using the file set from the builder
	var buf bytes.Buffer
	config := printer.Config{Mode: printer.UseSpaces, Tabwidth: 4}
	if err := config.Fprint(&buf, builder.GetFileSet(), goAST); err != nil {
		return "", nil
	}

	goCode := strings.TrimSpace(buf.String())

	// Add sourcemap comment
	sourcemapComment := sourcemap.GetSourceMapComment(sourceFile + ".map")
	goCode += "\n" + sourcemapComment

	// Build and return the source map that was created during transpilation
	sourceMap := builder.Build()
	return goCode, sourceMap
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

// PrintManuscriptErrorWithContext prints a user-friendly error with source context and ASCII arrow
func PrintManuscriptErrorWithContext(file string, line, column int, message string) {
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
	arrow := strings.Repeat(" ", column-1) + "^"
	fmt.Fprintf(os.Stderr, "\nError in %s at line %d, column %d:\n", file, line, column)
	fmt.Fprintf(os.Stderr, "%s\n%s\n%s\n\n", codeLine, arrow, message)
}
