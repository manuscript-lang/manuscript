package tooling

import (
	"github.com/manuscript-lang/manuscript/pkg/syntax"
	"strings"
)

// LintFinding is an advisory source hygiene diagnostic; checking owns semantic errors.
type LintFinding struct {
	Code     string          `json:"code"`
	Message  string          `json:"message"`
	Position syntax.Position `json:"position"`
}

func Lint(filename, source string) []LintFinding {
	findings := []LintFinding{}
	offset := 0
	for line, text := range strings.SplitAfter(source, "\n") {
		body := strings.TrimSuffix(strings.TrimSuffix(text, "\n"), "\r")
		trimmed := strings.TrimRight(body, " \t")
		if len(trimmed) != len(body) {
			findings = append(findings, LintFinding{"MSL001", "Remove trailing whitespace", syntax.Position{File: filename, Line: line + 1, Column: len(trimmed) + 1, Offset: offset + len(trimmed)}})
		}
		offset += len(text)
	}
	if source != "" && !strings.HasSuffix(source, "\n") {
		findings = append(findings, LintFinding{"MSL002", "End the file with a newline", syntax.Position{File: filename, Line: strings.Count(source, "\n") + 1, Column: len(source) - strings.LastIndex(source, "\n"), Offset: len(source)}})
	}
	return findings
}
