package tooling

import (
	"github.com/manuscript-lang/manuscript/checker"
	"github.com/manuscript-lang/manuscript/lexer"
	"github.com/manuscript-lang/manuscript/syntax"
	"sort"
	"strings"
)

// LintProgram adds semantic advisories from checked source. It never removes an
// initializer or changes runtime behavior; checker diagnostics own correctness.
func LintProgram(program *checker.Program) []LintFinding {
	findings := []LintFinding{}
	if program == nil || len(program.Diagnostics) > 0 {
		return findings
	}
	reads := map[*checker.Binding]int{}
	for _, info := range program.Expressions {
		if info != nil && info.Binding != nil {
			reads[info.Binding]++
		}
	}
	for pattern, binding := range program.Bindings {
		if binding != nil && reads[binding] == 0 && !strings.HasPrefix(binding.Name, "_") {
			findings = append(findings, LintFinding{"MSL101", "Local binding " + binding.Name + " is never read", pattern.Pos})
		}
	}
	for _, module := range program.Modules {
		tokens, err := lexer.Lex(module.File, module.Source)
		if err != nil {
			continue
		}
		importLines := map[int]bool{}
		for _, imp := range module.Imports {
			endLine := imp.NamePos.Line
			for _, token := range tokens {
				if token.Pos.Offset >= imp.Pos.Offset && token.Kind == lexer.String {
					endLine = token.Pos.Line
					break
				}
			}
			for line := imp.Pos.Line; line <= endLine; line++ {
				importLines[line] = true
			}
		}
		uses := map[string]bool{}
		for _, token := range tokens {
			if token.Kind == lexer.Name && !importLines[token.Pos.Line] {
				uses[token.Text] = true
			}
		}
		// List literals depend on the canonical import even without a written type name.
		for expression := range program.Expressions {
			if expression != nil && expression.Pos.File == module.File && expression.Kind == "list" {
				uses["List"] = true
			}
		}
		for _, imp := range module.Imports {
			if !uses[imp.Name] {
				findings = append(findings, LintFinding{"MSL102", "Import " + imp.Name + " is never used", imp.NamePos})
			}
		}
		var body func([]*syntax.Statement)
		var expression func(*syntax.Expression)
		expression = func(e *syntax.Expression) {
			if e == nil {
				return
			}
			body(e.Body)
			expression(e.Left)
			expression(e.Right)
			for _, arg := range e.Args {
				expression(arg.Value)
			}
			for _, item := range e.Elements {
				expression(item)
			}
		}
		body = func(statements []*syntax.Statement) {
			reachable := true
			for _, s := range statements {
				if !reachable {
					findings = append(findings, LintFinding{"MSL103", "Statement is unreachable", s.Pos})
				}
				if flow, ok := program.Flow[s]; ok && !flow.FallsThrough {
					reachable = false
				}
				body(s.Body)
				body(s.Else)
				for _, arm := range s.Arms {
					body(arm.Body)
				}
				expression(s.Value)
			}
		}
		for _, decl := range module.Declarations {
			body(decl.Body)
			for _, method := range decl.Methods {
				body(method.Body)
			}
		}
	}
	sort.Slice(findings, func(i, j int) bool {
		a, b := findings[i].Position, findings[j].Position
		if a.File != b.File {
			return a.File < b.File
		}
		if a.Offset != b.Offset {
			return a.Offset < b.Offset
		}
		return findings[i].Code < findings[j].Code
	})
	return findings
}
