package compile

import (
	"bytes"
	"errors"
	"fmt"
	"go/ast"
	"go/printer"
	"go/token"
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

// CompileOptions controls compilation behavior
type CompileOptions struct {
	StopAfter string // "tokens", "ast", "go", or empty for normal compilation
	Run       bool   // true to run the compiled code instead of writing to file
}

type CompileResult struct {
	GoCode    string
	SourceMap *sourcemap.SourceMap
	Error     error
}

const SyntaxErrorCode = "ERR_SYNTAX"

// Compile is the main compilation function
func Compile(filename string, cfg *config.MsConfig, opts CompileOptions) CompileResult {
	ctx, err := createCompilerContext(filename, cfg, opts.Run)
	if err != nil {
		return CompileResult{Error: err}
	}

	input, err := readSourceFile(ctx)
	if err != nil {
		return CompileResult{Error: err}
	}

	// Handle debug modes early
	if opts.StopAfter != "" {
		return handleDebugMode(input, ctx, opts.StopAfter)
	}

	// Normal compilation pipeline
	goCode, sourceMap, err := compileToGo(input, ctx)
	result := CompileResult{GoCode: goCode, SourceMap: sourceMap, Error: err}
	if err != nil {
		return result
	}

	// Handle execution or file writing
	if opts.Run {
		result.Error = executeCode(result)
	} else {
		result.Error = writeOutputFiles(ctx, result, cfg)
		if result.Error == nil {
			fmt.Printf("Compiled %s -> %s\n", ctx.SourceFile, ctx.GetOutputPath())
		}
	}

	return result
}

func createCompilerContext(filename string, cfg *config.MsConfig, runMode bool) (*config.CompilerContext, error) {
	sourceFile := filename
	if sourceFile == "" {
		sourceFile = cfg.CompilerOptions.EntryFile
	}
	if sourceFile == "" {
		return nil, errors.New("no source file specified")
	}

	workingDir := ""
	if !runMode {
		var err error
		workingDir, err = os.Getwd()
		if err != nil {
			return nil, fmt.Errorf("error getting current working directory: %v", err)
		}
	}

	return config.NewCompilerContext(cfg, workingDir, sourceFile)
}

func readSourceFile(ctx *config.CompilerContext) (string, error) {
	content, err := ctx.ModuleResolver.ResolveModule(ctx.SourceFile)
	if err != nil {
		return "", fmt.Errorf("failed to read file %s: %v", ctx.SourceFile, err)
	}
	return string(content), nil
}

func handleDebugMode(input string, ctx *config.CompilerContext, stopAfter string) CompileResult {
	switch stopAfter {
	case "tokens":
		printTokens(input)
		return CompileResult{}
	case "ast":
		tree, err := parseManuscript(input, ctx.SourceFile)
		if err != nil {
			return CompileResult{Error: err}
		}
		printParseTree(tree)
		return CompileResult{}
	case "go":
		goCode, sourceMap, err := compileToGo(input, ctx)
		if err != nil {
			return CompileResult{Error: err}
		}
		fmt.Println("\n=== GENERATED GO CODE ===")
		fmt.Println(goCode)
		fmt.Println()
		return CompileResult{GoCode: goCode, SourceMap: sourceMap}
	default:
		return CompileResult{Error: fmt.Errorf("unknown debug mode: %s", stopAfter)}
	}
}

// Core compilation pipeline
func compileToGo(input string, ctx *config.CompilerContext) (string, *sourcemap.SourceMap, error) {
	// Parse manuscript code
	tree, err := parseManuscript(input, ctx.SourceFile)
	if err != nil {
		return "", nil, err
	}

	// Convert to AST
	program, err := convertToAST(tree)
	if err != nil {
		return "", nil, err
	}

	// Transpile to Go
	goAST, sourceMap, err := transpileToGo(program, ctx)
	if err != nil {
		return "", nil, err
	}

	// Generate Go code
	goCode, err := generateGoCode(goAST)
	if err != nil {
		return "", nil, err
	}

	// Add sourcemap comment if needed
	if sourceMap != nil {
		goCode += "\n" + sourcemap.GetSourceMapComment(ctx.SourceFile+".map")
	}

	return goCode, sourceMap, nil
}

func parseManuscript(input string, sourceFile string) (antlr.ParseTree, error) {
	inputStream := antlr.NewInputStream(input)
	lexer := parser.NewManuscriptLexer(inputStream)
	stream := antlr.NewCommonTokenStream(lexer, antlr.TokenDefaultChannel)

	p := parser.NewManuscript(stream)
	errorListener := NewSyntaxErrorListener(sourceFile)
	p.RemoveErrorListeners()
	p.AddErrorListener(errorListener)

	tree := p.Program()
	if len(errorListener.Errors) > 0 {
		return nil, fmt.Errorf(SyntaxErrorCode)
	}

	return tree, nil
}

func convertToAST(tree antlr.ParseTree) (*mast.Program, error) {
	visitor := mastb.NewParseTreeToAST()
	result := tree.Accept(visitor)

	program, ok := result.(*mast.Program)
	if !ok {
		return nil, fmt.Errorf("failed to convert parse tree to AST")
	}

	return program, nil
}

func transpileToGo(program *mast.Program, ctx *config.CompilerContext) (*ast.File, *sourcemap.SourceMap, error) {
	var goTranspiler *transpiler.GoTranspiler
	var sourcemapBuilder *sourcemap.Builder

	if ctx.Config.CompilerOptions.Sourcemap && ctx.SourceFile != "" {
		sourcemapBuilder = sourcemap.NewBuilder(ctx.SourceFile, "generated.go")
		goTranspiler = transpiler.NewGoTranspilerWithSourceMap("main", sourcemapBuilder)
	} else {
		goTranspiler = transpiler.NewGoTranspiler("main")
	}

	visitedNode := goTranspiler.Visit(program)
	if visitedNode == nil {
		return nil, nil, fmt.Errorf("failed to transpile AST")
	}

	goAST, ok := visitedNode.(*ast.File)
	if !ok || goAST == nil {
		return nil, nil, fmt.Errorf("transpiler did not return a valid Go file")
	}

	var sourceMap *sourcemap.SourceMap
	if sourcemapBuilder != nil {
		sourceMap = sourcemapBuilder.Build()
	}

	return goAST, sourceMap, nil
}

func generateGoCode(goAST *ast.File) (string, error) {
	var buf bytes.Buffer
	config := printer.Config{Mode: printer.UseSpaces, Tabwidth: 4}
	if err := config.Fprint(&buf, token.NewFileSet(), goAST); err != nil {
		return "", fmt.Errorf("failed to print Go AST: %v", err)
	}

	return strings.TrimSpace(buf.String()), nil
}

func executeCode(result CompileResult) error {
	tmpFile, err := os.CreateTemp("", "manuscript_run_*.go")
	if err != nil {
		return fmt.Errorf("error creating temporary file: %v", err)
	}
	defer os.Remove(tmpFile.Name())
	defer tmpFile.Close()

	if _, err := tmpFile.WriteString(result.GoCode); err != nil {
		return fmt.Errorf("error writing temporary file: %v", err)
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

	return nil
}

func writeOutputFiles(ctx *config.CompilerContext, result CompileResult, cfg *config.MsConfig) error {
	outputPath := ctx.GetOutputPath()

	// Ensure output directory exists
	outputDir := filepath.Dir(outputPath)
	if err := os.MkdirAll(outputDir, 0755); err != nil {
		return fmt.Errorf("error creating output directory %s: %v", outputDir, err)
	}

	// Write Go code
	if err := os.WriteFile(outputPath, []byte(result.GoCode), 0644); err != nil {
		return fmt.Errorf("error writing output file %s: %v", outputPath, err)
	}

	// Write sourcemap if enabled
	if cfg.CompilerOptions.Sourcemap && result.SourceMap != nil {
		sourcemapFile := outputPath + ".map"
		if err := result.SourceMap.WriteToFile(sourcemapFile); err != nil {
			fmt.Fprintf(os.Stderr, "Warning: Failed to write sourcemap: %v\n", err)
		} else {
			fmt.Printf("Generated sourcemap: %s\n", sourcemapFile)
		}
	}

	return nil
}

// Debug helper functions
func printTokens(input string) {
	fmt.Println("\n=== TOKENS ===")
	inputStream := antlr.NewInputStream(input)
	lexer := parser.NewManuscriptLexer(inputStream)
	stream := antlr.NewCommonTokenStream(lexer, antlr.TokenDefaultChannel)
	stream.Fill()

	tokens := stream.GetAllTokens()
	for i, token := range tokens {
		if token.GetTokenType() == antlr.TokenEOF {
			fmt.Printf("Token %d: EOF\n", i)
		} else {
			fmt.Printf("Token %d: %s (%d:%d)\n", i, token.GetText(), token.GetLine(), token.GetColumn())
		}
	}
	fmt.Println()
}

func printParseTree(tree antlr.ParseTree) {
	fmt.Println("\n=== PARSE TREE ===")
	fmt.Println(tree.ToStringTree(nil, parser.NewManuscript(nil)))
	fmt.Println()
}

// Legacy functions for backward compatibility
func BuildFile(filename string, cfg *config.MsConfig) {
	result := Compile(filename, cfg, CompileOptions{})
	if result.Error != nil {
		fmt.Printf("Error: %v\n", result.Error)
	}
}

func CompileManuscriptFromString(msCode string, ctx *config.CompilerContext) (string, error) {
	goCode, _, err := compileToGo(msCode, ctx)
	return goCode, err
}

// Error mapping functions
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
		fmt.Fprintf(os.Stderr, "Error in %s at line %d, column %d: %s\n", file, line, column, message)
		return
	}

	lines := strings.Split(string(data), "\n")
	if line-1 < 0 || line-1 >= len(lines) {
		fmt.Fprintf(os.Stderr, "Error in %s at line %d, column %d: %s\n", file, line, column, message)
		return
	}

	fmt.Fprintf(os.Stderr, "\nError in %s at line %d, column %d:\n%s\n%s\n%s\n\n",
		file, line, column, lines[line-1],
		strings.Repeat(" ", column-1)+"^", message)
}
