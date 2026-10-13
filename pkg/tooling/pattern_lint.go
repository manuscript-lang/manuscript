package tooling

import (
	"fmt"
	"slices"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/checker"
)

func lintPatternBindings(program *checker.Program) []LintFinding {
	var findings []LintFinding
	for arm, conflicts := range program.ArmNameConflicts() {
		for index, conflict := range conflicts {
			name := arm.Names[index]
			if conflict == nil || name == "" || name[0] < 'A' || name[0] > 'Z' {
				continue
			}
			binding := program.ArmBindingsFor(arm)[index]
			if binding == nil {
				continue
			}
			identity := "a type name"
			if conflict.Case != "" {
				identity = "a visible alternative case name"
				if conflict.Type != nil {
					identity = "a case of " + conflict.Type.String()
				}
			}
			message := fmt.Sprintf("%s is %s, but this pattern creates a fresh binding for every %s payload; use a lowercase binding name if intentional", name, identity, binding.Type)
			if conflict.Case != "" && binding.Type.Kind == "alternative" && checker.Same(binding.Type, conflict.Type) {
				names := append([]string(nil), arm.Names...)
				payload := "payload"
				for suffix := 2; slices.Contains(names, payload); suffix++ {
					payload = fmt.Sprintf("payload%d", suffix)
				}
				names[index] = payload
				path := arm.Path.Text
				if target := program.ContractPattern(arm); target != nil {
					path = target.String()
				}
				nested := name
				for _, cs := range checker.Cases(binding.Type) {
					if cs.Name == name && len(cs.Fields) > 0 {
						ignored := make([]string, len(cs.Fields))
						for i := range ignored {
							ignored[i] = "_"
						}
						nested += "(" + strings.Join(ignored, ", ") + ")"
					}
				}
				message += fmt.Sprintf("; nested patterns are unsupported: write '%s(%s):', handle the payload in a separate helper using 'match %s:' with a '%s:' arm", path, strings.Join(names, ", "), payload, nested)
			}
			position := arm.Pos
			if index < len(arm.NamePositions) {
				position = arm.NamePositions[index]
			}
			findings = append(findings, LintFinding{Code: "MSL106", Message: message, Position: position})
		}
	}
	return findings
}
