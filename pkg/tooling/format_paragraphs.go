package tooling

import (
	"github.com/manuscript-lang/manuscript/pkg/syntax"
	"sort"
	"strings"
)

// paragraphBreaks adds space at syntax boundaries without changing expression
// layout or inferring the purpose of neighboring calls and bindings.
func paragraphBreaks(module *syntax.Module, lines []string) map[int]bool {
	breaks := map[int]bool{}
	before := func(line int) {
		// Keep leading comments with the node they describe, ignoring authored
		// blank lines. Stop at code or a different indentation level.
		indent := len(lines[line-1]) - len(strings.TrimLeft(lines[line-1], " "))
		for line > 1 {
			previous := lines[line-2]
			if strings.TrimSpace(previous) == "" {
				line--
				continue
			}
			if !strings.HasPrefix(strings.TrimSpace(previous), "#") ||
				len(previous)-len(strings.TrimLeft(previous, " ")) != indent {
				break
			}
			line--
		}
		breaks[line] = true
	}
	// Imports may be interleaved with declarations. Separate each import
	// section while keeping consecutive imports, and consecutive constants,
	// together.
	groups := map[int]string{}
	var topLevel []int
	for _, declaration := range module.Declarations {
		line := bindingLine(declaration.Pos, declaration.Group)
		topLevel = append(topLevel, line)
		if declaration.Constant {
			groups[line] = "constant"
		}
	}
	for _, item := range module.Imports {
		if groups[item.Pos.Line] == "" {
			topLevel = append(topLevel, item.Pos.Line)
		}
		groups[item.Pos.Line] = "import"
	}
	sort.Ints(topLevel)
	for i := 1; i < len(topLevel); i++ {
		if groups[topLevel[i-1]] == "" || groups[topLevel[i-1]] != groups[topLevel[i]] {
			before(topLevel[i])
		}
	}
	visitor := syntax.Visitor{
		Block: func(body []*syntax.Statement) {
			for i := 1; i < len(body); i++ {
				previous, current := body[i-1], body[i]
				line := bindingLine(current.Pos, current.Group)
				if bindingLine(previous.Pos, previous.Group) == line {
					continue
				}
				if paragraphBlock(previous) || paragraphBlock(current) ||
					(guardStatement(previous) && !guardStatement(current)) {
					before(line)
				}
			}
		},
	}
	for _, declaration := range module.Declarations {
		// Implementation bodies are separate reading units. Interface
		// signatures remain a compact list of the contract's operations.
		if declaration.Kind == syntax.KindImpl && len(declaration.Methods) > 1 {
			for _, method := range declaration.Methods[1:] {
				before(method.Pos.Line)
			}
		}
		visitor.Walk(declaration)
	}
	return breaks
}

// bindingLine is the line a binding starts on; a binding written in a
// `let (...)` or `var (...)` group starts on the group's keyword line, so the
// group moves as one unit and no blank line lands inside it.
func bindingLine(pos, group syntax.Position) int {
	if group.Line > 0 {
		return group.Line
	}
	return pos.Line
}

func guardStatement(statement *syntax.Statement) bool {
	if statement.Kind != syntax.KindIf || len(statement.Else) != 0 || len(statement.Body) != 1 {
		return false
	}
	switch statement.Body[0].Kind {
	case syntax.KindReturn, syntax.KindBreak, syntax.KindContinue:
		return true
	}
	return false
}

func paragraphBlock(statement *syntax.Statement) bool {
	// Single-step blocks belong to the surrounding cluster. Count syntax,
	// rather than source lines, so wrapping a header cannot add paragraphs on
	// the next formatting pass.
	if statement.Value != nil && statement.Value.Kind == syntax.KindMatch {
		return true
	}
	switch statement.Kind {
	case syntax.KindIf:
		return !guardStatement(statement) && (len(statement.Body) > 1 || len(statement.Else) > 0 ||
			(len(statement.Body) == 1 && paragraphBlock(statement.Body[0])))
	case syntax.KindWhile, syntax.KindFor, syntax.KindWith:
		return len(statement.Body) > 1 || (len(statement.Body) == 1 && paragraphBlock(statement.Body[0]))
	}
	return false
}
