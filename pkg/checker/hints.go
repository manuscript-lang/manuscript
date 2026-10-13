package checker

import (
	"sort"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// Diagnostics read "<cause>; <fix>". The cause comes first and keeps the
// stable wording rule codes classify; the fix names concrete source to write.

// closest returns the candidate most similar to name, or "" when none is near
// enough to be a plausible misspelling.
func closest(name string, candidates []string) string {
	best, bestDistance := "", 0
	if len(name) < 3 {
		return ""
	}
	limit := (len(name) + 2) / 3
	if limit > 3 {
		limit = 3
	}
	for _, candidate := range candidates {
		if candidate == name {
			continue
		}
		d := editDistance(strings.ToLower(name), strings.ToLower(candidate))
		if d <= limit && (best == "" || d < bestDistance || d == bestDistance && candidate < best) {
			best, bestDistance = candidate, d
		}
	}
	return best
}

func editDistance(a, b string) int {
	x, y := []rune(a), []rune(b)
	previous := make([]int, len(y)+1)
	for j := range previous {
		previous[j] = j
	}
	for i := 1; i <= len(x); i++ {
		current := make([]int, len(y)+1)
		current[0] = i
		for j := 1; j <= len(y); j++ {
			cost := 1
			if x[i-1] == y[j-1] {
				cost = 0
			}
			current[j] = min(previous[j]+1, current[j-1]+1, previous[j-1]+cost)
		}
		previous = current
	}
	return previous[len(y)]
}

// didYouMean returns "; did you mean 'x'?" for a near miss, else "".
func didYouMean(name string, candidates []string) string {
	if match := closest(name, candidates); match != "" {
		return "; did you mean '" + match + "'?"
	}
	return ""
}

// list renders at most limit sorted names for "available: ..." hints.
func list(names []string, limit int) string {
	names = uniqueSorted(names)
	more := ""
	if len(names) > limit {
		more = ", ..."
		names = names[:limit]
	}
	return strings.Join(names, ", ") + more
}

func uniqueSorted(names []string) []string {
	seen := map[string]bool{}
	var out []string
	for _, name := range names {
		if name != "" && !seen[name] {
			seen[name] = true
			out = append(out, name)
		}
	}
	sort.Strings(out)
	return out
}

// valueNames lists the bindings and declarations visible at the current scope.
func (c *checker) valueNames() []string {
	var names []string
	for s := c.scope; s != nil; s = s.parent {
		for name := range s.bindings {
			names = append(names, name)
		}
	}
	for name, symbol := range c.names {
		if symbol.Kind == syntax.KindFn {
			names = append(names, name)
		}
	}
	return names
}

func (c *checker) typeNames() []string {
	var names []string
	for s := c.scope; s != nil; s = s.parent {
		for name := range s.types {
			names = append(names, name)
		}
	}
	for name, symbol := range c.names {
		if symbol.Kind == syntax.KindType {
			names = append(names, name)
		}
	}
	return names
}

// importHint names the standard module that exports name, if any.
func importHint(name string) string {
	var modules []string
	for _, module := range StandardModuleNames() {
		if _, ok := StandardExports(module)[name]; ok {
			modules = append(modules, module)
		}
	}
	if len(modules) == 0 {
		return ""
	}
	return "; add: import " + name + " from \"" + modules[0] + "\""
}

// unknownName explains an unresolved value, preferring a near miss, then the
// standard module that provides the name, then the generic fix.
func (c *checker) unknownName(name string) string {
	c.unknownType = true // later "<invalid>" diagnostics only restate this one
	message := "unknown binding " + name
	if hint := didYouMean(name, c.valueNames()); hint != "" {
		return message + hint
	}
	if hint := importHint(name); hint != "" {
		return message + hint
	}
	return message + "; declare it with 'let " + name + " = ...' before use, define 'fn " + name + "(...)', or import it from a module"
}

// memberNames lists fields and operations available on a receiver type.
func (c *checker) memberNames(receiver *Type) []string {
	var names []string
	for _, f := range Fields(receiver) {
		names = append(names, f.Name)
	}
	if receiver.Def != nil {
		for _, op := range receiver.Def.Operations {
			names = append(names, op.Name)
		}
	}
	if intrinsic := intrinsicOperations[receiver.ID]; intrinsic != nil && intrinsic.Def != nil {
		for _, op := range intrinsic.Def.Operations {
			names = append(names, op.Name)
		}
	}
	if receiver.Kind == "variable" {
		for _, b := range receiver.Bounds {
			names = append(names, c.memberNames(b)...)
		}
	}
	for _, m := range c.Methods {
		if m.Decl == nil || !c.methodVisible(m) {
			continue
		}
		if unify(m.Receiver, receiver, variableSet(m.Variables), map[string]*Type{}) {
			names = append(names, m.Decl.Name)
		}
	}
	return uniqueSorted(names)
}

func (c *checker) unknownMember(receiver *Type, name string) string {
	c.unknownType = true
	message := "unknown or ambiguous member " + name + " on " + receiver.String()
	available := c.memberNames(receiver)
	if hint := didYouMean(name, available); hint != "" {
		return message + hint
	}
	if len(available) > 0 {
		return message + "; available: " + list(available, 12)
	}
	return message + "; this type has no fields or operations"
}

func paramNames(params []Param) []string {
	var names []string
	for _, p := range params {
		names = append(names, p.Name)
	}
	return names
}

func missingCases(cases []Case, seen map[string]bool) []string {
	var names []string
	for _, cs := range cases {
		if !seen[cs.Name] {
			names = append(names, cs.Name)
		}
	}
	return names
}

func typeSketch(name string, arity int) string {
	if arity == 0 {
		return name + " with no type arguments"
	}
	args := make([]string, arity)
	for i := range args {
		args[i] = "T" + string(rune('1'+i))
	}
	return name + "[" + strings.Join(args, ", ") + "]"
}

func (c *checker) unknownTypeMessage(name string) string {
	message := "unknown type " + name
	if hint := didYouMean(name, c.typeNames()); hint != "" {
		return message + hint
	}
	if hint := importHint(name); hint != "" {
		return message + hint
	}
	return message + "; declare it with 'type " + name + ":' / 'interface " + name + ":', declare it as a type parameter, or import it"
}

// exportMessage explains a failed import: the module lacks the name, or the
// name is private. It lists what the module does export.
func (c *checker) exportMessage(item *syntax.Import, imports map[*syntax.Import]string) string {
	message := "module does not export " + item.Name
	var exports []string
	if strings.HasPrefix(item.Path, "@std/") {
		if _, known := standardModules[item.Path]; !known {
			return message + "; unknown standard module " + item.Path + (didYouMean(item.Path, StandardModuleNames()))
		}
		for name := range StandardExports(item.Path) {
			exports = append(exports, name)
		}
	} else {
		for name, symbol := range c.Symbols[imports[item]] {
			if symbol.Export {
				exports = append(exports, name)
			} else if name == item.Name {
				return message + "; it is declared in " + item.Path + " but not exported, so write 'export' before its declaration"
			}
		}
	}
	if hint := didYouMean(item.Name, exports); hint != "" {
		return message + hint
	}
	if len(exports) == 0 {
		return message + "; " + item.Path + " exports nothing"
	}
	return message + "; " + item.Path + " exports: " + list(exports, 12)
}

// signatureText renders "(a: Int, b: String) -> Bool" for a function type.
func signatureText(t *Type) string {
	if t == nil || t.Kind != "function" {
		return ""
	}
	parts := make([]string, len(t.Params))
	for i, p := range t.Params {
		parts[i] = p.Name + ": " + p.Type.String()
	}
	return "(" + strings.Join(parts, ", ") + ") -> " + t.Result.String()
}
