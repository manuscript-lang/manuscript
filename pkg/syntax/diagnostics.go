package syntax

import (
	"encoding/json"
	"strings"
)

// Code groups stable rule families; message text remains readable and contextual.
func (d Diagnostic) Code() string {
	// Messages read "<cause>; <fix>". Only the cause identifies the rule.
	message, _, _ := strings.Cut(d.Message, "; ")
	switch d.Phase {
	case "parse":
		if strings.HasPrefix(message, "string-literal match patterns") {
			return "MS1000"
		}
		if strings.Contains(message, "indent") || strings.Contains(message, "suite") || strings.Contains(message, "tabs") {
			return "MS1002"
		}
		if strings.Contains(message, "UTF-8") || strings.Contains(message, "scalar") || strings.Contains(message, "escape") || strings.Contains(message, "literal") {
			return "MS1001"
		}
		return "MS1000"
	case "resolution":
		if strings.Contains(message, "module") || strings.Contains(message, "import") || strings.Contains(message, "path") || strings.Contains(message, "alias") {
			return "MS2002"
		}
		return "MS2001"
	case "type":
		for _, rule := range []struct{ needle, code string }{
			{"duplicate argument", "MS3002"}, {"missing argument", "MS3003"}, {"unknown argument", "MS3004"},
			{"overlapping implementation", "MS3010"}, {"signature does not match", "MS3011"}, {"nominal source data", "MS3012"},
			{"Hashable", "MS3021"}, {"captured", "MS3030"},
			{"recursive", "MS3040"}, {"exhaustive", "MS3050"}, {"immutable", "MS3060"}, {"literal", "MS3070"},
			{"infer", "MS3080"}, {"generic arity", "MS3080"}, {"expected ", "MS3001"}, {"same independently known type", "MS3001"},
		} {
			if strings.Contains(message, rule.needle) {
				return rule.code
			}
		}
		return "MS3000"
	case "lowering":
		return "MS4000"
	}
	return "MS0000"
}
func (d Diagnostic) MarshalJSON() ([]byte, error) {
	return json.Marshal(struct {
		Code     string         `json:"code"`
		Phase    string         `json:"phase"`
		Message  string         `json:"message"`
		Position Position       `json:"position"`
		End      *Position      `json:"end,omitempty"`
		Fix      *DiagnosticFix `json:"fix,omitempty"`
	}{d.Code(), d.Phase, d.Message, d.Position, d.End, d.Fix})
}
