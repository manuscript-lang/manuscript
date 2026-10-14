package lexer

import (
	"encoding/json"
	"os"
	"regexp"
	"slices"
	"sort"
	"strings"
	"testing"
)

// The VS Code TextMate grammar highlights exactly the reserved words.
func TestTextMateGrammarMatchesReservedWords(t *testing.T) {
	data, err := os.ReadFile("../../extensions/vscode/syntaxes/manuscript.tmLanguage.json")
	if err != nil {
		t.Fatal(err)
	}
	var grammar struct {
		Patterns []struct {
			Name  string `json:"name"`
			Match string `json:"match"`
		} `json:"patterns"`
	}
	if err := json.Unmarshal(data, &grammar); err != nil {
		t.Fatal(err)
	}
	words := regexp.MustCompile(`^\\b\(([a-z|]+)\)\\b$`)
	var highlighted []string
	for _, pattern := range grammar.Patterns {
		if pattern.Name != "keyword.control.manuscript" && pattern.Name != "constant.language.manuscript" {
			continue
		}
		if match := words.FindStringSubmatch(pattern.Match); match != nil {
			highlighted = append(highlighted, strings.Split(match[1], "|")...)
		}
	}
	sort.Strings(highlighted)
	if want := Keywords(); !slices.Equal(highlighted, want) {
		t.Fatalf("grammar words %v differ from reserved words %v", highlighted, want)
	}
}
