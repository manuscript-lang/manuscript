package tooling

import (
	"sort"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// DropRedundantLabels removes `name:` from an argument written `name: name`
// when the call binds the same parameter without it. An unlabeled argument fills
// the first parameter not supplied by an earlier argument, so a label is only
// dropped where that parameter is the labeled one. source is the text of one
// module of program. It reports the edited source and the number of labels
// removed, and changes nothing when the program has errors.
func DropRedundantLabels(program *checker.Program, source string) (string, int) {
	if program == nil || len(program.Diagnostics) > 0 {
		return source, 0
	}
	file, found := "", false
	for _, module := range program.Modules {
		if module.Source == source {
			file, found = module.File, true
			break
		}
	}
	if !found {
		return source, 0
	}
	type span struct{ from, to int }
	var cuts []span
	for e, info := range program.Expressions() {
		if e.Kind != syntax.KindCall || e.Pos.File != file || info == nil {
			continue
		}
		params, ok := callParameters(program, e, info)
		if !ok {
			continue
		}
		seen := make(map[string]bool, len(params))
		for _, arg := range e.Args {
			name := arg.Name
			if name == "" {
				for _, param := range params {
					if !seen[param.Name] {
						name = param.Name
						break
					}
				}
			} else if first := firstUnsupplied(params, seen); first == name && arg.Value.Kind == syntax.KindName && arg.Value.Text == name &&
				arg.Pos.Offset < arg.Value.Pos.Offset && arg.Value.Pos.Offset <= len(source) {
				cuts = append(cuts, span{arg.Pos.Offset, arg.Value.Pos.Offset})
			}
			seen[name] = true
		}
	}
	sort.Slice(cuts, func(i, j int) bool { return cuts[i].from > cuts[j].from })
	for _, cut := range cuts {
		source = source[:cut.from] + source[cut.to:]
	}
	return source, len(cuts)
}

func firstUnsupplied(params []checker.Param, seen map[string]bool) string {
	for _, param := range params {
		if !seen[param.Name] {
			return param.Name
		}
	}
	return ""
}

// callParameters returns the declared parameters of a function, method, or
// record constructor call. Alternative cases and contract views are skipped.
func callParameters(program *checker.Program, e *syntax.Expression, info *checker.Info) ([]checker.Param, bool) {
	switch {
	case info.Native == "view" || info.Case != "":
		return nil, false
	case info.Constructor != nil:
		return checker.ConstructorSignature(info.Constructor).Params, true
	}
	callee := program.Info(e.Left)
	if callee == nil || callee.Type == nil || callee.Type.Kind != "function" {
		return nil, false
	}
	return callee.Type.Params, true
}
