package tooling

import (
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// These preferences require equivalent, shipped call shapes and behavior.
// String.replace is deliberately absent: replace_first still accepts a cap
// greater than one, so it is not an unambiguous final replacement for that API.
var preferredNativeMethods = map[string]string{
	"@std/List/collections/with_value":  "List.set",
	"@std/List/collections/without":     "List.remove",
	"@std/List/collections/reverse":     "List.reverse_in_place",
	"@std/List/collections/with_values": "List.splice",
	"@std/Map/with_entry":               "Map.add",
	"@std/Map/without":                  "Map.remove",
	"@std/Set/with_value":               "Set.add",
	"@std/Set/without":                  "Set.remove",
	"@std/Bytes/bytes/reverse":          "Bytes.reversed",
	"@std/Regex/regex/replace":          "Regex.replace_all",
}

func lintPreferredNames(program *checker.Program) []LintFinding {
	var findings []LintFinding
	for expression, info := range program.Expressions {
		if expression.Kind != syntax.KindMember || info == nil || info.Method == nil || info.Method.Receiver == nil || info.Method.Contract != nil || strings.HasPrefix(expression.Pos.File, "@std/") {
			continue
		}
		method := info.Method
		preferred := preferredNativeMethods[method.Receiver.ID+"/"+method.Native]
		if preferred == "" {
			continue
		}
		behavior := "mutates and returns the receiver"
		switch method.Receiver.ID {
		case "@std/Bytes":
			behavior = "returns a copy"
		case "@std/Regex":
			behavior = "replaces all matches"
		}
		findings = append(findings, LintFinding{
			Code:     "MSL108",
			Message:  method.Receiver.Name + "." + expression.Text + " " + behavior + "; use " + preferred + " with the same arguments",
			Position: expression.Pos,
		})
	}
	return findings
}
