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
	reads := bindingReads(program)
	for pattern, binding := range program.PatternBindings() {
		if binding != nil && reads[binding] == 0 && !strings.HasPrefix(binding.Name, "_") {
			findings = append(findings, LintFinding{"MSL101", "Local binding " + binding.Name + " is never read", pattern.Pos})
		}
	}
	conflicts := map[*syntax.Arm][]*checker.Info{}
	for arm, found := range program.ArmNameConflicts() {
		conflicts[arm] = found
	}
	for arm, bindings := range program.ArmBindings() {
		for index, binding := range bindings {
			// MSL106 already explains a payload name that shadows a case or type.
			if index < len(conflicts[arm]) && conflicts[arm][index] != nil {
				continue
			}
			if binding != nil && reads[binding] == 0 && !strings.HasPrefix(binding.Name, "_") {
				findings = append(findings, LintFinding{"MSL101", "Local binding " + binding.Name + " is never read", armBindingPosition(arm, index)})
			}
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
	for expression, info := range program.Expressions() {
		if info != nil {
			mark(expression.Pos.File, info.Symbol)
		}
		// Collection literals require canonical imports even without written types.
		if expression.Kind == syntax.KindList {
			mark(expression.Pos.File, program.Symbol(expression.Pos.File, "List"))
		}
		if expression.Kind == syntax.KindMap {
			mark(expression.Pos.File, program.Symbol(expression.Pos.File, "Map"))
		}
	}
	for ref, typ := range program.TypeReferences() {
		if typ != nil && typ.Def != nil {
			mark(ref.Pos.File, typ.Def.Symbol)
		}
	}
	for _, module := range program.Modules {
		for _, imp := range module.Imports {
			if !uses[module.File][program.Symbol(module.File, imp.Name)] {
				findings = append(findings, LintFinding{"MSL102", "Import " + imp.Name + " is never used", imp.NamePos})
			}
		}
		visitor := syntax.Visitor{Block: func(statements []*syntax.Statement) {
			reachable := true
			for _, s := range statements {
				if !reachable {
					findings = append(findings, LintFinding{"MSL103", "Statement is unreachable", s.Pos})
				}
				if flow, ok := program.FlowOf(s); ok && !flow.FallsThrough {
					reachable = false
				}
			}
		}}
		for _, decl := range module.Declarations {
			visitor.Walk(decl)
		}

	}
	findings = append(findings, lintDiscardedResults(program)...)
	findings = append(findings, lintSharedCaptures(program)...)
	findings = append(findings, lintPatternBindings(program)...)
	findings = append(findings, lintNestedMatches(program)...)
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

// bindingReads counts reads of each binding. A read inside the right-hand
// side of an assignment to the same binding (`total = total + 2`) only feeds
// that binding's next value, so it does not make the binding observable.
func bindingReads(program *checker.Program) map[*checker.Binding]int {
	reads := map[*checker.Binding]int{}
	for _, info := range program.Expressions() {
		if info != nil && info.Binding != nil {
			reads[info.Binding]++
		}
	}
	for value := range program.Expressions() {
		assigned := program.AssignedBinding(value)
		if assigned == nil {
			continue
		}
		syntax.Visitor{Expression: func(e *syntax.Expression) {
			if info := program.Info(e); info != nil && info.Binding == assigned {
				reads[assigned]--
			}
		}}.Callable(nil, []*syntax.Statement{{Kind: syntax.KindReturn, Value: value}})
	}
	return reads
}

func armBindingPosition(arm *syntax.Arm, index int) syntax.Position {
	if index < len(arm.NamePositions) {
		return arm.NamePositions[index]
	}
	return arm.Pos
}
