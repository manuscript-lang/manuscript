package checker

import (
	"sort"
	"strconv"
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
	if symbol := standardSymbols[name]; isPreludeSymbol(symbol) {
		return "; use the prelude " + name + " declaration directly; rename any shadowing binding or declaration"
	}
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
	if name == "this" && c.scope.binding("self") != nil {
		return message + "; the receiver in an impl method is 'self'; write self instead of this"
	}
	if name == "pass" {
		return message + "; 'pass' is not a keyword, so write 'unit' for an empty block or match arm"
	}
	switch name {
	case "nil", "null", "None", "undefined":
		return message + "; Manuscript has no null: absence is an Optional, written none, and a present value is some(value)"
	case "print", "println", "printf", "puts", "echo":
		return message + "; there is no built-in print: import stdout from \"@std/io.ms\" and call stdout().write(\"text\\n\".to_bytes())"
	}
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
	return c.memberNamesSeen(receiver, map[*Type]bool{})
}

func (c *checker) memberNamesSeen(receiver *Type, seen map[*Type]bool) []string {
	if receiver == nil || seen[receiver] {
		return nil
	}
	seen[receiver] = true
	var names []string
	if receiver.Kind == syntax.KindRecord {
		for _, f := range Fields(receiver) {
			names = append(names, f.Name)
		}
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
			names = append(names, c.memberNamesSeen(b, seen)...)
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
	if receiver.Kind != syntax.KindRecord {
		for _, f := range Fields(receiver) {
			if f.Name == name {
				return "member " + name + " of " + receiver.String() + " is not readable or assignable; its state is reached only through its operations: " + strings.Join(available, ", ")
			}
		}
	}
	if std(receiver, "List") && name == "join" {
		return message + "; join is only available on List[String]; convert the elements first, e.g. xs.map(transform: fn(value: Int) -> String: \"{value}\").join(separator: \",\")"
	}
	if hint := synonymHint(name, available); hint != "" {
		return message + hint
	}
	if hint := didYouMean(name, available); hint != "" {
		return message + hint
	}
	if len(available) > 0 {
		if len(available) <= 40 {
			return message + "; available: " + strings.Join(available, ", ")
		}
		var same []string
		for _, candidate := range available {
			if name != "" && candidate[0] == name[0] {
				same = append(same, candidate)
			}
		}
		if len(same) > 0 {
			return message + "; available starting with '" + name[:1] + "': " + strings.Join(same, ", ") + "; " + strconv.Itoa(len(available)) + " members in total"
		}
		return message + "; available: " + list(available, 40)
	}
	return message + "; this type has no fields or operations"
}

// memberSynonyms maps names guessed from other languages to the members that
// usually mean the same thing here.
var memberSynonyms = map[string][]string{
	"len": {"length", "byte_length", "scalar_length"}, "size": {"length", "byte_length", "scalar_length"}, "count": {"length", "byte_length", "scalar_length"},
	"length": {"byte_length", "scalar_length"},
	"push":   {"append", "add"}, "add": {"append"}, "insert": {"append", "add"},
	"delete":    {"remove"},
	"to_string": {"to_text"}, "decode": {"to_text"}, "toString": {"to_text"},
}

func synonymHint(name string, available []string) string {
	var found []string
	for _, candidate := range memberSynonyms[name] {
		for _, a := range available {
			if a == candidate {
				found = append(found, "'"+candidate+"'")
			}
		}
	}
	if len(found) == 0 {
		return ""
	}
	return "; did you mean " + strings.Join(found, " or ") + "?"
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
	if hint := importHint(name); hint != "" {
		return message + hint
	}
	if hint := didYouMean(name, c.typeNames()); hint != "" {
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
		if _, native := standardModules[item.Path]; !native && standardSourceModules[item.Path] == nil {
			return message + "; unknown standard module " + item.Path + (didYouMean(item.Path, StandardModuleNames()))
		}
		for name := range StandardExports(item.Path) {
			exports = append(exports, name)
		}
	} else {
		for name, symbol := range c.symbols[imports[item]] {
			if symbol.Module != imports[item] || symbol.Decl == nil {
				continue
			}
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
		return message + "; " + item.Path + " exports nothing; namespace imports are unsupported, so import individual exported declarations"
	}
	return message + "; " + item.Path + " exports: " + list(exports, 12) + "; namespace imports are unsupported, so import individual exports with 'import { Name, OtherName } from \"" + item.Path + "\"'"
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

// assignmentMismatch adds a view hint only when the expected type itself is
// an interface. Collections and other invariant containers need their own
// element conversions and cannot be converted by wrapping the whole value.
func (c *checker) assignmentMismatch(actual, expected *Type) string {
	message := formatMismatch(actual, expected)
	if hint := labelMismatchHint(actual, expected); hint != "" {
		return message + "; " + hint
	}
	if hint := optionalUseHint(actual, expected); hint != "" {
		return message + "; " + hint
	}
	if hint := numberConversionHint(actual, expected); hint != "" {
		return message + "; " + hint
	}
	if hint := uncalledFunctionHint(actual, expected); hint != "" {
		return message + "; " + hint
	}
	if expected.Kind != "contract" || actual == nil || actual.ID == "<invalid>" {
		return message
	}
	if c.implements(actual, expected) {
		return message + "; " + actual.String() + " implements " + expected.String() + "; write " + expected.String() + "(value: ...) to create an explicit interface view"
	}
	if actual.Def != nil && actual.Def.Symbol != nil && actual.Def.Symbol.Native == "" && (actual.Kind == syntax.KindRecord || actual.Kind == "alternative") {
		return message + "; no applicable 'impl " + expected.String() + " for " + actual.String() + "' is visible; declare an implementation before creating an interface view"
	}
	return message + "; use a concrete value implementing " + expected.String() + " and create its explicit interface view with " + expected.String() + "(value: ...)"
}

func (c *checker) interfaceTypeMember(typ *Type) string {
	c.unknownType = true
	return typ.String() + " is an interface, not an alternative; declare a concrete type and 'impl " + typ.String() + " for <Type>:', then construct that concrete type"
}

// labelMismatchHint explains function types that differ in parameter names
// (labels), which are part of a function's identity.
func labelMismatchHint(actual, expected *Type) string {
	if actual == nil || expected == nil || actual.Kind != "function" || expected.Kind != "function" || len(actual.Params) != len(expected.Params) {
		return ""
	}
	for i, p := range actual.Params {
		if p.Name != expected.Params[i].Name {
			return "the function's parameter is named " + p.Name + " but this position expects " + expected.Params[i].Name + "; rename the parameter to " + expected.Params[i].Name + ", or wrap the function in a lambda: fn(" + expected.Params[i].Name + ": ...) -> ...: f(" + p.Name + ": " + expected.Params[i].Name + ")"
		}
	}
	return ""
}

// optionalUseHint names the fix when an Optional is used where a plain value
// is required: the value may be absent, so it has to be unwrapped first.
func optionalUseHint(actual, expected *Type) string {
	if actual == nil || expected == nil || !std(actual, "Optional") || len(actual.Args) != 1 || std(expected, "Optional") {
		return ""
	}
	return actual.String() + " may be absent; unwrap it first with unwrap_or(default), is_some() before unwrap(), or match"
}

// numberConversionHint names the explicit conversion between Int and Float;
// neither converts implicitly.
func numberConversionHint(actual, expected *Type) string {
	if actual == nil || expected == nil {
		return ""
	}
	switch {
	case actual.ID == "Int" && expected.ID == "Float":
		return "Int does not convert to Float implicitly; write a Float literal such as 3.0, or call to_float() on an Int value"
	case actual.ID == "Float" && expected.ID == "Int":
		return "Float does not convert to Int implicitly; truncate_to_int() returns Optional[Int], so unwrap it, e.g. value.truncate_to_int().unwrap_or(0)"
	}
	return ""
}

// uncalledFunctionHint covers a no-argument operation named without
// parentheses, such as items.length where items.length() is meant.
func uncalledFunctionHint(actual, expected *Type) string {
	if actual == nil || expected == nil || actual.Kind != "function" || expected.Kind == "function" || len(actual.Params) != 0 || actual.Result == nil || !Same(actual.Result, expected) {
		return ""
	}
	return "this is a function; call it with parentheses to get its " + expected.String() + " result"
}
