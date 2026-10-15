package mcp

import (
	"encoding/json"
	"fmt"
	"path/filepath"
	"strings"
)

// Tool results are read by a model every call, so each one reports only what
// it needs to act on: failures, locations, and counts, never whole documents.

const (
	maxLines    = 40
	maxText     = 6000
	maxFailure  = 600
	maxEntities = 120
)

// clip keeps the head and tail of long text, where errors and summaries usually sit.
func clip(s string, limit int) string {
	if len(s) <= limit {
		return s
	}
	head, tail := limit*2/3, limit/3
	return s[:head] + fmt.Sprintf("\n[... %d bytes omitted ...]\n", len(s)-head-tail) + s[len(s)-tail:]
}

type diagnostic struct {
	Code     string `json:"code"`
	Message  string `json:"message"`
	Position struct {
		File   string `json:"file"`
		Line   int    `json:"line"`
		Column int    `json:"column"`
	} `json:"position"`
}

func diagnosticLines(list []diagnostic) []string {
	lines := make([]string, 0, min(len(list), maxLines)+1)
	for i, d := range list {
		if i == maxLines {
			lines = append(lines, fmt.Sprintf("... %d more", len(list)-maxLines))
			break
		}
		lines = append(lines, fmt.Sprintf("%s:%d:%d %s %s", d.Position.File, d.Position.Line, d.Position.Column, d.Code, d.Message))
	}
	return lines
}

// diagnosticsReport renders check and lint results.
func diagnosticsReport(raw string) string {
	var doc struct {
		Diagnostics []diagnostic `json:"diagnostics"`
	}
	if json.Unmarshal([]byte(raw), &doc) != nil {
		return clip(raw, maxText)
	}
	if len(doc.Diagnostics) == 0 {
		return "ok: no diagnostics"
	}
	return fmt.Sprintf("%d diagnostics\n%s", len(doc.Diagnostics), strings.Join(diagnosticLines(doc.Diagnostics), "\n"))
}

// formatReport lists the files that need formatting.
func formatReport(raw string) string {
	var doc struct {
		Files []struct {
			Path   string `json:"path"`
			Status string `json:"status"`
		} `json:"files"`
		Diagnostics []diagnostic `json:"diagnostics"`
	}
	if json.Unmarshal([]byte(raw), &doc) != nil {
		return clip(raw, maxText)
	}
	var dirty []string
	for _, f := range doc.Files {
		if f.Status != "clean" {
			dirty = append(dirty, relative(f.Path))
		}
	}
	if len(dirty) == 0 && len(doc.Diagnostics) == 0 {
		return "ok: all formatted"
	}
	var lines []string
	if len(dirty) > 0 {
		lines = append(lines, "needs formatting (set write to fix): "+strings.Join(dirty, ", "))
	}
	for _, d := range doc.Diagnostics {
		if d.Code != "MSF001" {
			lines = append(lines, diagnosticLines([]diagnostic{d})...)
		}
	}
	return clip(strings.Join(lines, "\n"), maxText)
}

func relative(path string) string {
	if !filepath.IsAbs(path) {
		return path
	}
	if wd, err := filepath.Abs("."); err == nil {
		if rel, err := filepath.Rel(wd, path); err == nil && !strings.HasPrefix(rel, "..") {
			return rel
		}
	}
	return path
}

// testReport summarizes a test run and details only what failed.
func testReport(raw string) string {
	var doc struct {
		Tests []struct {
			Name    string `json:"name"`
			Status  string `json:"status"`
			Failure string `json:"failure"`
		} `json:"tests"`
		Summary struct {
			Selected, Passed, Failed, Skipped int
		} `json:"summary"`
		Completed     bool   `json:"completed"`
		ExitCode      int    `json:"exit_code"`
		Reason        string `json:"reason"`
		FixtureErrors []struct {
			File    string `json:"file"`
			Failure string `json:"failure"`
		} `json:"fixture_errors"`
		Diagnostics []diagnostic `json:"diagnostics"`
	}
	if json.Unmarshal([]byte(raw), &doc) != nil {
		return clip(raw, maxText)
	}
	var lines []string
	head := fmt.Sprintf("%d passed, %d failed", doc.Summary.Passed, doc.Summary.Failed)
	if doc.Summary.Skipped > 0 {
		head += fmt.Sprintf(", %d skipped", doc.Summary.Skipped)
	}
	if !doc.Completed {
		head += " (run did not complete"
		if doc.Reason != "" {
			head += ": " + doc.Reason
		}
		head += ")"
	}
	lines = append(lines, head)
	shown := 0
	for _, t := range doc.Tests {
		if t.Status != "failed" {
			continue
		}
		if shown++; shown > 10 {
			lines = append(lines, "... more failures")
			break
		}
		lines = append(lines, "FAIL "+t.Name+": "+clip(t.Failure, maxFailure))
	}
	for _, f := range doc.FixtureErrors {
		lines = append(lines, "fixture "+f.File+": "+clip(f.Failure, maxFailure))
	}
	lines = append(lines, diagnosticLines(doc.Diagnostics)...)
	return strings.Join(lines, "\n")
}

// buildReport reports success or the reasons a build failed.
func buildReport(raw string) string {
	var doc struct {
		Completed   bool         `json:"completed"`
		ExitCode    int          `json:"exit_code"`
		Output      string       `json:"output"`
		Stdout      string       `json:"stdout"`
		Diagnostics []diagnostic `json:"diagnostics"`
	}
	if json.Unmarshal([]byte(raw), &doc) != nil {
		return clip(raw, maxText)
	}
	if doc.Completed && len(doc.Diagnostics) == 0 {
		return "ok: built " + doc.Output
	}
	lines := []string{fmt.Sprintf("build failed (exit %d)", doc.ExitCode)}
	lines = append(lines, diagnosticLines(doc.Diagnostics)...)
	if len(doc.Diagnostics) == 0 && doc.Stdout != "" {
		lines = append(lines, clip(doc.Stdout, 2000))
	}
	return strings.Join(lines, "\n")
}

// inspectReport lists declarations rather than the full inspection document.
func inspectReport(raw string) string {
	var doc struct {
		Entities []struct {
			Kind string `json:"kind"`
			Name string `json:"name"`
			Type string `json:"type"`
			Span struct {
				File string `json:"file"`
				Line int    `json:"line"`
			} `json:"span"`
		} `json:"entities"`
		Diagnostics []diagnostic `json:"diagnostics"`
	}
	if json.Unmarshal([]byte(raw), &doc) != nil {
		return clip(raw, maxText)
	}
	if len(doc.Diagnostics) > 0 {
		return diagnosticsReport(raw)
	}
	var b strings.Builder
	for i, e := range doc.Entities {
		if i == maxEntities {
			fmt.Fprintf(&b, "... %d more\n", len(doc.Entities)-maxEntities)
			break
		}
		fmt.Fprintf(&b, "%s %s", e.Kind, e.Name)
		if e.Type != "" {
			fmt.Fprintf(&b, ": %s", e.Type)
		}
		fmt.Fprintf(&b, " (%s:%d)\n", e.Span.File, e.Span.Line)
	}
	return strings.TrimRight(b.String(), "\n")
}

// symbolReport renders hover, definition, and references on a few lines.
func symbolReport(hover, definition string, references []string, diagnostics int) string {
	var lines []string
	if hover = strings.TrimSpace(hover); hover != "" {
		code, docs := hover, ""
		if inner, rest, found := strings.Cut(strings.TrimPrefix(hover, "```manuscript\n"), "\n```"); found {
			code, docs = inner, firstSentence(rest)
		}
		lines = append(lines, "type: "+strings.ReplaceAll(code, "\n", " "))
		if docs != "" {
			lines = append(lines, docs)
		}
	} else {
		lines = append(lines, "no symbol at this position")
	}
	if definition != "" {
		lines = append(lines, "defined: "+relative(definition))
	}
	if n := len(references); n > 0 {
		shown := make([]string, 0, min(n, 15))
		for _, ref := range references[:min(n, 15)] {
			shown = append(shown, relative(ref))
		}
		line := fmt.Sprintf("references (%d): %s", n, strings.Join(shown, ", "))
		if n > len(shown) {
			line += ", ..."
		}
		lines = append(lines, line)
	}
	if diagnostics > 0 {
		lines = append(lines, fmt.Sprintf("note: file has %d errors, results may be partial", diagnostics))
	}
	return strings.Join(lines, "\n")
}
