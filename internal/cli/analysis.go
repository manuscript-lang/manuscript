package cli

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
	"github.com/manuscript-lang/manuscript/pkg/tooling"
)

type analyzedInput struct {
	input  analysisInput
	result compiler.Result
}

func analyzeSelection(command string, selection analysisSelection) ([]analyzedInput, []syntax.Diagnostic) {
	var inputs []analyzedInput
	issues := append([]syntax.Diagnostic{}, selection.diagnostics...)
	for _, input := range selection.inputs {
		options := compiler.Options{AnalyzeOnly: true, ProjectSources: command == "check", Entry: command != "lint" && filepath.Base(input.path) == "ms.toml"}
		result := compiler.CompileFile(input.path, options)
		inputs = append(inputs, analyzedInput{input, result})
		for _, issue := range result.Diagnostics {
			issues = append(issues, selection.diagnostic(result.SourceRoot, issue))
		}
	}
	return inputs, issues
}

func lintFindings(result compiler.Result) []tooling.LintFinding {
	findings := []tooling.LintFinding{}
	for _, module := range result.Program.Modules {
		if !strings.HasPrefix(module.File, "@std/") {
			findings = append(findings, tooling.Lint(module.File, module.Source)...)
		}
	}
	for _, finding := range tooling.LintProgram(result.Program) {
		if !strings.HasPrefix(finding.Position.File, "@std/") {
			findings = append(findings, finding)
		}
	}
	return findings
}

func runAnalysis(command string, targets []string, structured bool) int {
	selection, err := selectAnalysisInputs(targets)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	inputs, issues := analyzeSelection(command, selection)
	diagnostics := []commandDiagnostic{}
	for _, issue := range issues {
		diagnostics = append(diagnostics, sourceDiagnostic(issue))
	}
	for _, input := range inputs {
		if !input.result.Success() {
			continue
		}
		if command == "lint" {
			for _, finding := range lintFindings(input.result) {
				diagnostics = append(diagnostics, commandDiagnostic{Code: finding.Code, Message: finding.Message, Position: selection.position(input.result.SourceRoot, finding.Position)})
			}
		} else if !structured {
			if input.result.ProjectRoot != "" {
				count := 0
				for _, module := range input.result.Program.Modules {
					if !strings.HasPrefix(module.File, "@std/") {
						count++
					}
				}
				fmt.Printf("Checked %s (%d %s)\n", input.input.display, count, plural(count, "module", "modules"))
			} else {
				fmt.Println("Checked", input.input.display)
			}
		}
	}
	if selection.collection {
		diagnostics = orderedAnalysisDiagnostics(diagnostics)
	}
	status := 0
	if len(diagnostics) > 0 {
		status = 1
	}
	if structured {
		document := diagnosticsDocument{1, diagnostics}
		return emitJSON(document, status)
	}
	for _, issue := range diagnostics {
		if !selection.collection && len(inputs) == 1 && inputs[0].result.SourceRoot != "" && !filepath.IsAbs(issue.Position.File) {
			issue.Position.File = filepath.Join(inputs[0].result.SourceRoot, issue.Position.File)
		}
		label := issue.Phase
		if label == "" {
			label = issue.Code
		}
		fmt.Fprintf(os.Stderr, "%s: %s: %s\n", issue.Position, label, issue.Message)
	}
	if len(issues) > 0 {
		count := 0
		for _, issue := range diagnostics {
			if issue.Phase != "" {
				count++
			}
		}
		fmt.Fprintf(os.Stderr, "%d %s; fix them and re-run (ms check <file> --json gives the same diagnostics as structured data)\n", count, plural(count, "error", "errors"))
	}
	return status
}

func orderedAnalysisDiagnostics(issues []commandDiagnostic) []commandDiagnostic {
	seen := map[string]bool{}
	unique := issues[:0]
	for _, issue := range issues {
		data, _ := json.Marshal(issue)
		if key := string(data); !seen[key] {
			seen[key] = true
			unique = append(unique, issue)
		}
	}
	sort.SliceStable(unique, func(i, j int) bool {
		a, b := unique[i], unique[j]
		if a.Position.File != b.Position.File {
			return a.Position.File < b.Position.File
		}
		if a.Position.Line != b.Position.Line {
			return a.Position.Line < b.Position.Line
		}
		if a.Position.Column != b.Position.Column {
			return a.Position.Column < b.Position.Column
		}
		if a.Code != b.Code {
			return a.Code < b.Code
		}
		return a.Message < b.Message
	})
	return unique
}

func reportAnalysisErrors(selection analysisSelection, inputs []analyzedInput, issues []syntax.Diagnostic) int {
	root := ""
	if !selection.collection && len(inputs) == 1 {
		root = inputs[0].result.SourceRoot
	}
	if selection.collection {
		diagnostics := make([]commandDiagnostic, 0, len(issues))
		for _, issue := range issues {
			diagnostics = append(diagnostics, sourceDiagnostic(issue))
		}
		issues = issues[:0]
		for _, issue := range orderedAnalysisDiagnostics(diagnostics) {
			issues = append(issues, syntax.Diagnostic{Position: issue.Position, Phase: issue.Phase, Message: issue.Message, End: issue.End, Fix: issue.Fix})
		}
	}
	return reportDiagnostics(compiler.Result{SourceRoot: root, Diagnostics: issues})
}
