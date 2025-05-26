package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"

	"manuscript-lang/manuscript/internal/compile"
	"manuscript-lang/manuscript/internal/config"

	"kr.dev/diff"
)

const (
	testDir     = "../tests/compilation"
	packageMain = "package main"
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
	Content  *[]byte                 // Pointer to shared content that gets updated
	Config   *config.CompilerOptions // Test-specific configuration
}

func TestManuscriptTranspile(t *testing.T) {
	runTestsOnMarkdownFiles(t, runParseTest)
}

func TestDumpTokens(t *testing.T) {
	content := `let x = 1`
	ctx := createTestContext(t)
	actualGo, err := compile.CompileManuscriptFromString(content, ctx)
	if err != nil {
		t.Fatalf("manuscriptToGo failed: %v", err)
	}
	if !strings.HasPrefix(actualGo, packageMain) {
		t.Fatalf("manuscriptToGo should return package main: %s", actualGo)
	}
}

func createTestContext(t *testing.T) *config.CompilerContext {
	ctx, err := config.NewCompilerContextFromFile("test.ms", "", "")
	if err != nil {
		t.Fatalf("Failed to create test context: %v", err)
	}

	// Set debug flag if the test flag is enabled
	if *debug {
		ctx.Debug = true
	}

	return ctx
}

func runParseTest(t *testing.T, ctx *TestPairContext) {
	// Create compiler context for this test
	compilerCtx := createTestContext(t)

	// If test has specific config, merge it
	if ctx.Config != nil {
		compilerCtx.Config.Merge(ctx.Config)
	}

	goCode, err := compile.CompileManuscriptFromString(ctx.Pair.MsCode, compilerCtx)
	if err != nil {
		if err.Error() == compile.SyntaxErrorCode && ctx.Pair.GoCode == compile.SyntaxErrorCode {
			return
		}
		t.Fatalf("CompileManuscriptFromString failed: %v", err)
	}
	if *update {
		updateTestContent(ctx, goCode)
		return
	}
	assertGoCode(t, goCode, ctx.Pair.GoCode)
}

func updateTestContent(ctx *TestPairContext, actualGo string) {
	// Update the shared content in memory
	updatedContent := strings.Replace(string(*ctx.Content), ctx.Pair.GoCode, actualGo, 1)
	*ctx.Content = []byte(updatedContent)
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

	// Shared state for all tests in this file
	sharedContent := content

	for i, pair := range testPairs {
		testName := getTestName(pair, i)
		t.Run(testName, func(t *testing.T) {
			ctx := &TestPairContext{
				Pair:     pair,
				FilePath: filePath,
				Content:  &sharedContent,
			}
			testFunc(t, ctx)
		})
	}

	// Write the file back if any updates were made
	if *update {
		if err := os.WriteFile(filePath, sharedContent, 0644); err != nil {
			t.Fatalf("Failed to update test file %s: %v", filePath, err)
		}
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
