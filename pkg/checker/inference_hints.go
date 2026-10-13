package checker

import "strings"

func missingTypeArgumentHint(name, missing string, variables, arguments []*Type) string {
	parts := make([]string, len(variables))
	for index, variable := range variables {
		parts[index] = variable.Name
		if index < len(arguments) && arguments[index] != nil && !invalidType(arguments[index]) {
			parts[index] = arguments[index].String()
		}
	}
	return "cannot infer type argument " + missing + " for " + name + "; write " + name + "[" + strings.Join(parts, ", ") + "](...) with an explicit type for " + missing + "; call arguments and the expected result must determine every type parameter"
}
