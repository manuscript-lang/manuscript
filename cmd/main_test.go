package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"

	"kr.dev/diff"
)

var (
	fileFilter = flag.String("file", "", "Filter test files by a suffix of their name (without .md extension)")
	debug      = flag.Bool("debug", false, "Enable token dumping for debugging")
	update     = flag.Bool("update", false, "Update Go code snapshots in markdown test files")
)

func TestMain(m *testing.M) {
	flag.Parse()
	os.Exit(m.Run())
}

func assertGoCode(t *testing.T, actual, expected string) {
	if actual != expected {
		diff.Test(t, t.Errorf, expected, actual)
	}
}

// TestPair holds a single test case parsed from a markdown file,
// consisting of a title, a manuscript code block, and its expected Go code output.
type TestPair struct {
	Title  string
	MsCode string
	GoCode string
}

func TestCompile(t *testing.T) {
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

			testPairs := parseMarkdownTest(string(content))

			if len(testPairs) == 0 {
				t.Logf("No manuscript/go test pairs found in %s", file.Name())
				return
			}

			for i, pair := range testPairs {
				testSubName := ""
				if pair.Title != "" {
					testSubName = pair.Title
				} else {
					testSubName = fmt.Sprintf("pair_%d", i+1) // 1-indexed for readability
				}

				t.Run(testSubName, func(t *testing.T) {
					actualGo, err := manuscriptToGo(pair.MsCode, *debug)
					if err != nil {
						t.Fatalf("manuscriptToGo failed: %v", err)
					}
					if *update && pair.GoCode != actualGo {
						content = []byte(strings.Replace(string(content), pair.GoCode, actualGo, 1))
						err = os.WriteFile(filePath, content, 0644)
						if err != nil {
							t.Fatalf("Failed to update test file %s: %v", filePath, err)
						}
					}
					assertGoCode(t, actualGo, pair.GoCode)
				})
			}
		})
	}
}

func TestDumpTokens(t *testing.T) {
	content := `
	let x = 1
	`
	actualGo, err := manuscriptToGo(content, true)
	if err != nil {
		t.Fatalf("manuscriptToGo failed: %v", err)
	}
	if !strings.HasPrefix(actualGo, "package main") {
		t.Fatalf("manuscriptToGo should return package main: %s", actualGo)
	}
}

// findTitleForMsBlock searches for the most relevant title for a manuscript code block.
// It looks for a title that appears after the last processed Go block and before the current ms block.
// If multiple such titles exist, the one closest to the ms block is chosen.
func findTitleForMsBlock(msBlockStartOffset int, lastGoBlockEndOffset int, allTitleMatches [][]int, markdownContent string) string {
	currentPairTitle := ""
	bestTitleStartForPair := -1

	for _, titleMatchIndices := range allTitleMatches {
		titleText := strings.TrimSpace(markdownContent[titleMatchIndices[2]:titleMatchIndices[3]])
		titleStartOffset := titleMatchIndices[0]
		titleEndOffset := titleMatchIndices[1]

		// Title must be after the last go block and before the current ms block
		if titleStartOffset >= lastGoBlockEndOffset && titleEndOffset < msBlockStartOffset {
			// If multiple titles fit, choose the latest one (closest to ms block)
			if titleStartOffset > bestTitleStartForPair {
				bestTitleStartForPair = titleStartOffset
				currentPairTitle = titleText
			}
		}
	}
	return currentPairTitle
}

// parseMarkdownTest extracts ordered pairs of manuscript and go code blocks,
// along with their preceding titles.
func parseMarkdownTest(content string) []TestPair {
	// Regex to find fenced code blocks and capture the language tag and the body
	codeBlockRegex := regexp.MustCompile("(?s)```\\s*(\\w+)\\s*\n(.*?)\n```")
	// Regex to find titles (lines starting with #)
	titleRegex := regexp.MustCompile("(?m)^#\\s+(.*)$")

	matches := codeBlockRegex.FindAllStringSubmatchIndex(content, -1)
	allTitleMatches := titleRegex.FindAllStringSubmatchIndex(content, -1)

	var testPairs []TestPair
	lastGoBlockEndOffset := 0

	for i := 0; i < len(matches)-1; i++ {
		b1Indices := matches[i]
		b2Indices := matches[i+1]

		lang1 := strings.TrimSpace(content[b1Indices[2]:b1Indices[3]])
		msBody := strings.TrimSpace(content[b1Indices[4]:b1Indices[5]])

		lang2 := strings.TrimSpace(content[b2Indices[2]:b2Indices[3]])
		goBody := strings.TrimSpace(content[b2Indices[4]:b2Indices[5]])

		if lang1 == "ms" && lang2 == "go" {
			msBlockStartOffset := b1Indices[0]

			currentPairTitle := findTitleForMsBlock(msBlockStartOffset, lastGoBlockEndOffset, allTitleMatches, content)

			testPairs = append(testPairs, TestPair{
				Title:  currentPairTitle,
				MsCode: msBody,
				GoCode: goBody,
			})

			lastGoBlockEndOffset = b2Indices[1] // Update for the next search window for titles
			i++                                 // Consumed two blocks, advance main loop index
		}
	}
	return testPairs
}
