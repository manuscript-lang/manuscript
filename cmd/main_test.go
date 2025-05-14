package main

import (
	"flag"
	"fmt"
	"log"
	parser "manuscript-co/manuscript/internal/parser"
	codegen "manuscript-co/manuscript/internal/visitor"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"

	"kr.dev/diff"

	"github.com/antlr4-go/antlr/v4"
)

var (
	fileFilter = flag.String("file", "", "Filter test files by a suffix of their name (without .md extension)")
	debug      = flag.Bool("debug", false, "Enable token dumping for debugging")
)

func TestMain(m *testing.M) {
	flag.Parse()
	os.Exit(m.Run())
}

func manuscriptToGo(t *testing.T, input string) string {
	inputStream := antlr.NewInputStream(input)
	lexer := parser.NewManuscriptLexer(inputStream)
	tokenStream := antlr.NewCommonTokenStream(lexer, antlr.TokenDefaultChannel)

	if *debug {
		dumpTokens(tokenStream)
	}

	p := parser.NewManuscript(tokenStream)
	tree := p.Program()
	codeGen := codegen.NewCodeGenerator()
	goCode, err := codeGen.Generate(tree)
	if err != nil {
		t.Fatalf("codeGen.Generate failed: %v", err)
	}
	return strings.TrimSpace(goCode)
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

func assertGoCode(t *testing.T, actual, expected string) {
	if actual != expected {
		diff.Test(t, t.Errorf, expected, actual)
	}
}

func TestMarkdownCompilation(t *testing.T) {
	testDir := "../tests/compilation"
	allFiles, err := os.ReadDir(testDir)
	if err != nil {
		t.Fatalf("Failed to read test directory %s: %v", testDir, err)
	}

	var testFilesToRun []os.DirEntry
	for _, file := range allFiles {
		if file.IsDir() || !strings.HasSuffix(file.Name(), ".md") {
			continue
		}
		if *fileFilter != "" {
			nameWithoutExt := strings.TrimSuffix(file.Name(), filepath.Ext(file.Name()))
			if strings.HasSuffix(nameWithoutExt, *fileFilter) {
				testFilesToRun = append(testFilesToRun, file)
			}
		} else {
			testFilesToRun = append(testFilesToRun, file)
		}
	}

	if len(testFilesToRun) == 0 {
		if *fileFilter != "" {
			t.Fatalf("No .md files matching filter '%s' found in %s", *fileFilter, testDir)
		} else {
			t.Logf("No .md files found in %s to test.", testDir)
			return
		}
	}

	for _, file := range testFilesToRun {
		t.Run(file.Name(), func(t *testing.T) {
			filePath := filepath.Join(testDir, file.Name())
			content, err := os.ReadFile(filePath)
			if err != nil {
				t.Fatalf("Failed to read test file %s: %v", filePath, err)
			}

			msInputs, goExpectedOutputs := parseMarkdownTest(string(content))

			if len(msInputs) == 0 {
				t.Logf("No manuscript/go test pairs found in %s", file.Name())
				return
			}

			if len(msInputs) != len(goExpectedOutputs) {
				t.Fatalf("Mismatch in parsed manuscript and go code block counts in %s. Inputs: %d, Outputs: %d",
					file.Name(), len(msInputs), len(goExpectedOutputs))
			}

			baseName := strings.TrimSuffix(file.Name(), ".md")
			for i, msInput := range msInputs {
				goExpected := goExpectedOutputs[i]
				t.Run(fmt.Sprintf("%s_pair%d", baseName, i), func(t *testing.T) {
					actualGo := manuscriptToGo(t, msInput)
					assertGoCode(t, actualGo, goExpected)
				})
			}
		})
	}
}

// parseMarkdownTest extracts ordered pairs of manuscript and go code blocks.
func parseMarkdownTest(markdownContent string) (msCodes []string, goCodes []string) {
	// Regex to find fenced code blocks and capture the language tag and the body
	codeBlockRegex := regexp.MustCompile("(?s)```\\s*(\\w+)\\s*\n(.*?)\n```")
	allMatches := codeBlockRegex.FindAllStringSubmatch(markdownContent, -1)

	i := 0
	for i < len(allMatches)-1 {
		lang1 := strings.TrimSpace(allMatches[i][1])
		body1 := strings.TrimSpace(allMatches[i][2])
		lang2 := strings.TrimSpace(allMatches[i+1][1])
		body2 := strings.TrimSpace(allMatches[i+1][2])

		if lang1 == "ms" && lang2 == "go" {
			msCodes = append(msCodes, body1)
			goCodes = append(goCodes, body2)
			i += 2
		} else {
			i++
		}
	}
	return msCodes, goCodes
}
