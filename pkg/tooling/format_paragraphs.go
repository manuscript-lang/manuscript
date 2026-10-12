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
		// Keep contiguous leading comments with the node they describe. Stop at
		// an existing paragraph or a different indentation level.
		indent := len(lines[line-1]) - len(strings.TrimLeft(lines[line-1], " "))
		for line > 1 {
			previous := lines[line-2]
			if !strings.HasPrefix(strings.TrimSpace(previous), "#") ||
				len(previous)-len(strings.TrimLeft(previous, " ")) != indent {
				break
			}
			line--
		}
		breaks[line] = true
	}
	// Imports may be interleaved with declarations. Separate each import
	// section while keeping consecutive imports together.
	imports := map[int]bool{}
	var topLevel []int
	for _, declaration := range module.Declarations {
		topLevel = append(topLevel, declaration.Pos.Line)
	}
	for _, item := range module.Imports {
		if !imports[item.Pos.Line] {
			topLevel = append(topLevel, item.Pos.Line)
		}
		imports[item.Pos.Line] = true
	}
	sort.Ints(topLevel)
	for i := 1; i < len(topLevel); i++ {
		if !imports[topLevel[i-1]] || !imports[topLevel[i]] {
			before(topLevel[i])
		}
	}
	indentedArm := func(arm syntax.Arm) bool {
		header, body := lines[arm.Pos.Line-1], lines[arm.Body[0].Pos.Line-1]
		return len(body)-len(strings.TrimLeft(body, " ")) >
			len(header)-len(strings.TrimLeft(header, " "))
	}
	visitor := syntax.Visitor{
		Block: func(body []*syntax.Statement) {
			for i := 1; i < len(body); i++ {
				previous, current := body[i-1], body[i]
				if previous.Pos.Line == current.Pos.Line {
					continue
				}
				if paragraphBlock(previous) || paragraphBlock(current) ||
					(guardStatement(previous) && !guardStatement(current)) {
					before(current.Pos.Line)
				}
			}
		},
		Statement: func(statement *syntax.Statement) {
			for i := 1; i < len(statement.Arms); i++ {
				previous, current := statement.Arms[i-1], statement.Arms[i]
				if indentedArm(previous) || indentedArm(current) {
					before(current.Pos.Line)
				}
			}
		},
	}
	for _, declaration := range module.Declarations {
		// Implementation bodies are separate reading units. Interface
		// signatures remain a compact list of the contract's operations.
		if declaration.Kind == syntax.KindImpl {
			for _, method := range declaration.Methods[1:] {
				before(method.Pos.Line)
			}
		}
		visitor.Walk(declaration)
	}
	return breaks
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
	switch statement.Kind {
	case syntax.KindIf:
		return !guardStatement(statement)
	case syntax.KindWhile, syntax.KindFor, syntax.KindWith, syntax.KindMatch:
		return true
	}
	return false
}
