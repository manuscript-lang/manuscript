package tooling

import (
	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
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
	// Use the checker's resolved identities, not a second lexical approximation.
	uses := map[string]map[*checker.Symbol]bool{}
	mark := func(file string, symbol *checker.Symbol) {
		if symbol == nil {
			return
		}
		if uses[file] == nil {
			uses[file] = map[*checker.Symbol]bool{}
		}
		uses[file][symbol] = true
	}
	for expression, info := range program.Expressions {
		if info != nil {
			mark(expression.Pos.File, info.Symbol)
		}
		// List literals require the canonical import even without a written type.
		if expression.Kind == syntax.KindList {
			mark(expression.Pos.File, program.Symbols[expression.Pos.File]["List"])
		}
	}
	for ref, typ := range program.TypeReferences {
		if typ != nil && typ.Def != nil {
			mark(ref.Pos.File, typ.Def.Symbol)
		}
	}
	for _, module := range program.Modules {
		for _, imp := range module.Imports {
			if !uses[module.File][program.Symbols[module.File][imp.Name]] {
				findings = append(findings, LintFinding{"MSL102", "Import " + imp.Name + " is never used", imp.NamePos})
			}
		}
		visitor := syntax.Visitor{Block: func(statements []*syntax.Statement) {
			reachable := true
			for _, s := range statements {
				if !reachable {
					findings = append(findings, LintFinding{"MSL103", "Statement is unreachable", s.Pos})
				}
				if flow, ok := program.Flow[s]; ok && !flow.FallsThrough {
					reachable = false
				}
			}
		}}
		for _, decl := range module.Declarations {
			visitor.Walk(decl)
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
