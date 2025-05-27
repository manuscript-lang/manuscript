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

const testDir = "../tests/compilation"

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
	Content  *[]byte
	Config   *config.CompilerOptions
}

func TestManuscriptTranspile(t *testing.T) {
	testFiles := getTestFiles(t)

	for _, file := range testFiles {
		t.Run(file.Name(), func(t *testing.T) {
			runTestsInFile(t, file)
		})
	}
}

func createTestContext(t *testing.T) *config.CompilerContext {
	ctx, err := config.NewCompilerContextFromFile("test.ms", "", "")
	if err != nil {
		t.Fatalf("Failed to create test context: %v", err)
	}

	if *debug {
		ctx.Debug = true
	}

	return ctx
}

func runParseTest(t *testing.T, ctx *TestPairContext) {
	compilerCtx := createTestContext(t)

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
		updatedContent := strings.Replace(string(*ctx.Content), ctx.Pair.GoCode, goCode, 1)
		*ctx.Content = []byte(updatedContent)
		return
	}

	if goCode != ctx.Pair.GoCode {
		diff.Test(t, t.Errorf, ctx.Pair.GoCode, goCode)
	}
}

func getTestFiles(t *testing.T) []os.DirEntry {
	allFiles, err := os.ReadDir(testDir)
	if err != nil {
		t.Fatalf("Failed to read test directory %s: %v", testDir, err)
	}

	var testFiles []os.DirEntry
	for _, file := range allFiles {
		if file.IsDir() || !strings.HasSuffix(file.Name(), ".md") {
			continue
		}

		if *fileFilter != "" {
			nameWithoutExt := strings.TrimSuffix(file.Name(), filepath.Ext(file.Name()))
			if !strings.HasSuffix(nameWithoutExt, *fileFilter) {
				continue
			}
		}

		testFiles = append(testFiles, file)
	}

	if len(testFiles) == 0 {
		if *fileFilter != "" {
			t.Fatalf("No .md files matching filter '%s' found in %s", *fileFilter, testDir)
		} else {
			t.Logf("No .md files found in %s to test.", testDir)
		}
	}

	return testFiles
}

func runTestsInFile(t *testing.T, file os.DirEntry) {
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

	sharedContent := content

	for i, pair := range testPairs {
		testName := pair.Title
		if testName == "" {
			testName = fmt.Sprintf("pair_%d", i+1)
		}

		t.Run(testName, func(t *testing.T) {
			ctx := &TestPairContext{
				Pair:     pair,
				FilePath: filePath,
				Content:  &sharedContent,
			}
			runParseTest(t, ctx)
		})
	}

	if *update {
		if err := os.WriteFile(filePath, sharedContent, 0644); err != nil {
			t.Fatalf("Failed to update test file %s: %v", filePath, err)
		}
	}
}

func parseMarkdownTest(content string) []TestPair {
	matches := codeBlockRegex.FindAllStringSubmatchIndex(content, -1)
	allTitleMatches := titleRegex.FindAllStringSubmatchIndex(content, -1)

	var testPairs []TestPair
	lastGoBlockEndOffset := 0

	for i := 0; i < len(matches)-1; i++ {
		b1Indices := matches[i]
		b2Indices := matches[i+1]

		lang1 := strings.TrimSpace(content[b1Indices[2]:b1Indices[3]])
		lang2 := strings.TrimSpace(content[b2Indices[2]:b2Indices[3]])

		if lang1 != "ms" || lang2 != "go" {
			continue
		}

		msBody := strings.TrimSpace(content[b1Indices[4]:b1Indices[5]])
		goBody := strings.TrimSpace(content[b2Indices[4]:b2Indices[5]])
		title := findTitleForMsBlock(b1Indices[0], lastGoBlockEndOffset, allTitleMatches, content)

		testPairs = append(testPairs, TestPair{
			Title:  title,
			MsCode: msBody,
			GoCode: goBody,
		})

		lastGoBlockEndOffset = b2Indices[1]
		i++ // Skip the next match since we consumed two blocks
	}
	return testPairs
}

func findTitleForMsBlock(msBlockStartOffset, lastGoBlockEndOffset int, allTitleMatches [][]int, content string) string {
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
