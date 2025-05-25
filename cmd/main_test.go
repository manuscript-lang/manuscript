package main

import (
	"bytes"
	"flag"
	"fmt"
	"go/ast"
	"go/printer"
	"go/token"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"

	mast "manuscript-co/manuscript/internal/ast"
	"manuscript-co/manuscript/internal/msparse"
	"manuscript-co/manuscript/internal/parser"
	"manuscript-co/manuscript/internal/transpiler"

	"github.com/antlr4-go/antlr/v4"
	"kr.dev/diff"
)

const (
	testDir         = "../tests/compilation"
	syntaxErrorCode = "// SYNTAX ERROR"
	packageMain     = "package main"
)

var (
	fileFilter = flag.String("file", "", "Filter test files by a suffix of their name (without .md extension)")
	debug      = flag.Bool("debug", false, "Enable token dumping for debugging")
	update     = flag.Bool("update", false, "Update Go code snapshots in markdown test files")
)

var (
	codeBlockRegex = regexp.MustCompile("(?s)```\\s*(\\w+)\\s*\\n(.*?)\\n```")
	titleRegex     = regexp.MustCompile(`(?m)^#\s+(.*)$`)
)

func TestMain(m *testing.M) {
	flag.Parse()
	os.Exit(m.Run())
}

type TestPair struct {
	Title  string
	MsCode string
	GoCode string
}

type TestPairContext struct {
	Pair     TestPair
	FilePath string
	Content  []byte
}

func TestCompile(t *testing.T) {
	runTestsOnMarkdownFiles(t, runCompileTest)
}

func TestParseAllManuscriptCode(t *testing.T) {
	runTestsOnMarkdownFiles(t, runParseTest)
}

func TestDumpTokens(t *testing.T) {
	content := `let x = 1`
	actualGo, err := manuscriptToGo(content, true)
	if err != nil {
		t.Fatalf("manuscriptToGo failed: %v", err)
	}
	if !strings.HasPrefix(actualGo, packageMain) {
		t.Fatalf("manuscriptToGo should return package main: %s", actualGo)
	}
}

func runCompileTest(t *testing.T, ctx *TestPairContext) {
	pair := ctx.Pair
	actualGo, err := manuscriptToGo(pair.MsCode, *debug)
	expectSyntaxErr := strings.TrimSpace(pair.GoCode) == syntaxErrorCode

	handleCompileResult(t, ctx, actualGo, err, expectSyntaxErr)
}

func runParseTest(t *testing.T, ctx *TestPairContext) {
	goCode := parseManuscriptAST(t, ctx.Pair.MsCode)
	assertGoCode(t, goCode, ctx.Pair.GoCode)
}

func handleCompileResult(
	t *testing.T,
	ctx *TestPairContext,
	actualGo string,
	err error,
	expectSyntaxErr bool,
) {
	switch {
	case err != nil && expectSyntaxErr:
		validateSyntaxError(t, err)
	case err != nil && !expectSyntaxErr:
		t.Fatalf("manuscriptToGo failed: %v", err)
	case err == nil && expectSyntaxErr:
		t.Fatalf("Expected syntax error, but got output:\n%s", actualGo)
	default:
		handleSuccessfulCompile(t, ctx, actualGo)
	}
}

func validateSyntaxError(t *testing.T, err error) {
	if strings.Contains(err.Error(), "syntax error") {
		t.Logf("Correctly failed with syntax error: %v", err)
	} else {
		t.Fatalf("Expected syntax error, got: %v", err)
	}
}

func handleSuccessfulCompile(t *testing.T, ctx *TestPairContext, actualGo string) {
	if *update && ctx.Pair.GoCode != actualGo {
		updateTestFile(t, ctx, actualGo)
	}
	assertGoCode(t, actualGo, ctx.Pair.GoCode)
}

func updateTestFile(t *testing.T, ctx *TestPairContext, actualGo string) {
	content := []byte(strings.Replace(string(ctx.Content), ctx.Pair.GoCode, actualGo, 1))
	if err := os.WriteFile(ctx.FilePath, content, 0644); err != nil {
		t.Fatalf("Failed to update test file %s: %v", ctx.FilePath, err)
	}
}

func assertGoCode(t *testing.T, actual, expected string) {
	if actual != expected {
		diff.Test(t, t.Errorf, expected, actual)
	}
}

func runTestsOnMarkdownFiles(
	t *testing.T,
	testFunc func(*testing.T, *TestPairContext),
) {
	testFiles := getTestFiles(t)

	for _, file := range testFiles {
		t.Run(file.Name(), func(t *testing.T) {
			runTestsInFile(t, file, testFunc)
		})
	}
}

func getTestFiles(t *testing.T) []os.DirEntry {
	allFiles, err := os.ReadDir(testDir)
	if err != nil {
		t.Fatalf("Failed to read test directory %s: %v", testDir, err)
	}

	var testFiles []os.DirEntry
	for _, file := range allFiles {
		if shouldIncludeFile(file) {
			testFiles = append(testFiles, file)
		}
	}

	validateTestFiles(t, testFiles)
	return testFiles
}

func shouldIncludeFile(file os.DirEntry) bool {
	if file.IsDir() || !strings.HasSuffix(file.Name(), ".md") {
		return false
	}

	if *fileFilter == "" {
		return true
	}

	nameWithoutExt := strings.TrimSuffix(file.Name(), filepath.Ext(file.Name()))
	return strings.HasSuffix(nameWithoutExt, *fileFilter)
}

func validateTestFiles(t *testing.T, testFiles []os.DirEntry) {
	if len(testFiles) == 0 {
		if *fileFilter != "" {
			t.Fatalf("No .md files matching filter '%s' found in %s", *fileFilter, testDir)
		} else {
			t.Logf("No .md files found in %s to test.", testDir)
		}
	}
}

func runTestsInFile(
	t *testing.T,
	file os.DirEntry,
	testFunc func(*testing.T, *TestPairContext),
) {
	filePath := filepath.Join(testDir, file.Name())
	content, err := os.ReadFile(filePath)
	if err != nil {
		t.Fatalf("Failed to read test file %s: %v", filePath, err)
	}

	testPairs := parseMarkdownTest(string(content))
	if len(testPairs) == 0 {
		t.Logf("No manuscript/go test pairs found in %s", file.Name())
		return
	}

	for i, pair := range testPairs {
		testName := getTestName(pair, i)
		t.Run(testName, func(t *testing.T) {
			ctx := &TestPairContext{
				Pair:     pair,
				FilePath: filePath,
				Content:  content,
			}
			testFunc(t, ctx)
		})
	}
}

func getTestName(pair TestPair, index int) string {
	if pair.Title != "" {
		return pair.Title
	}
	return fmt.Sprintf("pair_%d", index+1)
}

func parseMarkdownTest(content string) []TestPair {
	matches := codeBlockRegex.FindAllStringSubmatchIndex(content, -1)
	allTitleMatches := titleRegex.FindAllStringSubmatchIndex(content, -1)

	var testPairs []TestPair
	lastGoBlockEndOffset := 0

	for i := 0; i < len(matches)-1; i++ {
		if pair, newOffset, consumed := tryParseTestPair(content, matches, i, lastGoBlockEndOffset, allTitleMatches); consumed {
			testPairs = append(testPairs, pair)
			lastGoBlockEndOffset = newOffset
			i++ // Skip the next match since we consumed two blocks
		}
	}
	return testPairs
}

func tryParseTestPair(
	content string,
	matches [][]int,
	index, lastGoBlockEndOffset int,
	allTitleMatches [][]int,
) (TestPair, int, bool) {
	b1Indices := matches[index]
	b2Indices := matches[index+1]

	lang1 := strings.TrimSpace(content[b1Indices[2]:b1Indices[3]])
	lang2 := strings.TrimSpace(content[b2Indices[2]:b2Indices[3]])

	if lang1 != "ms" || lang2 != "go" {
		return TestPair{}, 0, false
	}

	msBody := strings.TrimSpace(content[b1Indices[4]:b1Indices[5]])
	goBody := strings.TrimSpace(content[b2Indices[4]:b2Indices[5]])
	title := findTitleForMsBlock(b1Indices[0], lastGoBlockEndOffset, allTitleMatches, content)

	pair := TestPair{
		Title:  title,
		MsCode: msBody,
		GoCode: goBody,
	}

	return pair, b2Indices[1], true
}

func findTitleForMsBlock(
	msBlockStartOffset, lastGoBlockEndOffset int,
	allTitleMatches [][]int,
	content string,
) string {
	var bestTitle string
	bestTitleStart := -1

	for _, titleMatch := range allTitleMatches {
		titleStart := titleMatch[0]
		titleEnd := titleMatch[1]

		if titleStart >= lastGoBlockEndOffset && titleEnd < msBlockStartOffset && titleStart > bestTitleStart {
			bestTitleStart = titleStart
			bestTitle = strings.TrimSpace(content[titleMatch[2]:titleMatch[3]])
		}
	}

	return bestTitle
}

func parseManuscriptAST(t *testing.T, msCode string) string {
	tree, hasErrors := parseManuscriptCode(msCode)
	if hasErrors {
		t.Logf("Parsing failed with syntax errors (as expected for some test cases)")
		return syntaxErrorCode
	}

	return convertToGoCode(t, tree)
}

func parseManuscriptCode(msCode string) (parser.IProgramContext, bool) {
	inputStream := antlr.NewInputStream(msCode)
	lexer := parser.NewManuscriptLexer(inputStream)
	stream := antlr.NewCommonTokenStream(lexer, antlr.TokenDefaultChannel)
	p := parser.NewManuscript(stream)

	errorListener := NewSyntaxErrorListener()
	p.RemoveErrorListeners()
	p.AddErrorListener(errorListener)

	tree := p.Program()
	return tree, len(errorListener.Errors) > 0
}

func convertToGoCode(t *testing.T, tree parser.IProgramContext) string {
	visitor := msparse.NewParseTreeToAST()
	result := tree.Accept(visitor)

	mnode, ok := result.(*mast.Program)
	if !ok {
		t.Errorf("Failed to convert parse tree to AST program")
		return ""
	}

	transpiler := transpiler.NewGoTranspiler("main")
	goNode := transpiler.Visit(mnode)
	if goNode == nil {
		t.Errorf("Failed to convert parse tree to AST program")
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
