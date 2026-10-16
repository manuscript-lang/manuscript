// Package checker resolves names and verifies Manuscript's nominal type system.
package checker

import (
	"fmt"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
	"strings"
)

type Type struct {
	Name, ID, Kind string
	Args           []*Type
	Params         []Param
	Result         *Type
	Def            *Definition
	Bounds         []*Type
	// Default is a type variable's default argument, in terms of earlier variables.
	Default *Type
	// Defaults marks omittable parameters on a known source callable.
	// It is erased by explicit function types and generic inference.
	Defaults map[string]bool
}
type Param struct {
	Name string
	Type *Type
}

// Operation retains a receiver or contract operation's signature and source
// identity, so defaults declared by a contract reach its implementations.
type Operation struct {
	Name string
	Type *Type
	Decl *syntax.Declaration
}
type Definition struct {
	Symbol     *Symbol
	Kind       string
	Variables  []*Type
	Fields     []Param
	Cases      []Case
	Operations []Operation
}
type Case struct {
	Name   string
	Fields []Param
}
type Symbol struct {
	Name, ID, Kind, Module, Native string
	Export                         bool
	Type                           *Type
	Variables                      []*Type
	Decl                           *syntax.Declaration
}
type Binding struct {
	Name, ID string
	Type     *Type
	Mutable  bool
	Function int
	// nonNegative: an Int that starts at a written nonnegative value and is
	// only assigned nonnegative values or incremented by one.
	nonNegative bool
}
type Method struct {
	ID                       string
	Module                   string
	Local                    bool
	Receiver, Contract, Type *Type
	Variables                []*Type
	Decl                     *syntax.Declaration
	Native                   string
}

// VisibleIn keeps extensions in their declaring module. Implementations owned
// by the receiver's defining module remain available wherever the type is used.
func (m *Method) VisibleIn(module string) bool {
	return !m.Local || m.Module == module
}

type Info struct {
	Type        *Type
	Symbol      *Symbol
	Binding     *Binding
	Constructor *Type
	Case        string
	Method      *Method
	Native      string
	NoReturn    bool
	Breaks      bool
	Write       bool
	Captures    []*Binding
	TypeArgs    []*Type
	// ErrorSource retains the concrete type when an Error boundary accepts it.
	ErrorSource       *Type
	ScopedError       bool
	PropagatedError   *Type
	ScopedPropagation bool
	// Arguments retains written order with omitted function labels resolved.
	Arguments []syntax.Argument
	// OptionalArgument wraps this supplied argument once without changing its source type.
	OptionalArgument *Type
	// Folded reports that the expression is a compile-time Bool constant whose
	// value is Constant. The fold pass sets both.
	Folded, Constant bool
	foldDone         bool
	// Proven reports an index expression the checker proved in range, so its
	// type is the element type; lowering keeps a faulting read.
	Proven bool
	// inferenceDeferred records body checks that need a later callback result context.
	inferenceDeferred bool
}
type Flow struct{ FallsThrough bool }

// TestFixture preserves the checked factory identity and concrete injected type.
type TestFixture struct {
	Factory *Symbol
	Type    *Type
	Hooks   *Type // the standard TestHooks contract the fixture implements
}

type Program struct {
	TestFixtures map[string]*TestFixture
	Effects      map[string][]string
	Modules      []*syntax.Module
	symbols      map[string]map[string]*Symbol
	Methods      []*Method
	Diagnostics  []syntax.Diagnostic
	serial       int // identities handed out while checking
}

func (t *Type) String() string {
	if t == nil {
		return "<unknown>"
	}
	if t.Kind == "function" {
		var p []string
		for _, a := range t.Params {
			label := a.Name + ": " + a.Type.String()
			if t.Defaults[a.Name] {
				label += " = ..."
			}
			p = append(p, label)
		}
		return "fn(" + strings.Join(p, ", ") + ")->" + t.Result.String()
	}
	s := t.Name
	if len(t.Args) > 0 {
		var a []string
		for _, v := range t.Args {
			a = append(a, v.String())
		}
		s += "[" + strings.Join(a, ", ") + "]"
	}
	return s
}
func Same(a, b *Type) bool {
	if a == nil || b == nil {
		return false
	}
	if a.ID != b.ID || a.Kind != b.Kind || len(a.Args) != len(b.Args) || len(a.Params) != len(b.Params) {
		return false
	}
	for i := range a.Args {
		if !Same(a.Args[i], b.Args[i]) {
			return false
		}
	}
	if a.Kind == "function" {
		for i, p := range a.Params {
			if p.Name != b.Params[i].Name || !Same(p.Type, b.Params[i].Type) {
				return false
			}
		}
		return Same(a.Result, b.Result)
	}
	return true
}
func compatible(actual, expected *Type) bool {
	return actual != nil && (actual.ID == "Never" || Same(actual, expected))
}
func Sub(t *Type, bindings map[string]*Type) *Type {
	if t == nil {
		return nil
	}
	if v, ok := bindings[t.ID]; ok {
		return v
	}
	r := *t
	r.Args = nil
	for _, a := range t.Args {
		r.Args = append(r.Args, Sub(a, bindings))
	}
	r.Params = nil
	for _, p := range t.Params {
		r.Params = append(r.Params, Param{p.Name, Sub(p.Type, bindings)})
	}
	r.Result = Sub(t.Result, bindings)
	return &r
}
func requiredType(t *Type) *Type {
	if t == nil {
		return nil
	}
	r := *t
	r.Defaults = nil
	r.Args = nil
	for _, a := range t.Args {
		r.Args = append(r.Args, requiredType(a))
	}
	r.Params = nil
	for _, p := range t.Params {
		r.Params = append(r.Params, Param{p.Name, requiredType(p.Type)})
	}
	r.Result = requiredType(t.Result)
	return &r
}
func substitution(t *Type) map[string]*Type {
	r := map[string]*Type{}
	if t.Def != nil {
		for i, v := range t.Def.Variables {
			if i < len(t.Args) {
				r[v.ID] = t.Args[i]
			}
		}
	}
	return r
}
func Fields(t *Type) []Param {
	var result []Param
	if t.Def != nil {
		for _, p := range t.Def.Fields {
			result = append(result, Param{p.Name, Sub(p.Type, substitution(t))})
		}
	}
	return result
}

// ConstructorSignature describes constructor inputs and omission permissions.
// Native constructor inputs need not be readable data fields.
func ConstructorSignature(t *Type) *Type {
	params := Fields(t)
	if std(t, "Bytes") {
		params = []Param{{"values", standard("List", primitive("Int"))}}
	}
	signature := function(params, t)
	if t.Def != nil && t.Def.Symbol != nil && t.Def.Symbol.Decl != nil {
		for _, field := range t.Def.Symbol.Decl.Fields {
			if field.Default != nil {
				if signature.Defaults == nil {
					signature.Defaults = map[string]bool{}
				}
				signature.Defaults[field.Name] = true
			}
		}
	}
	return signature
}
func Cases(t *Type) []Case {
	var result []Case
	if t.Def != nil {
		for _, c := range t.Def.Cases {
			r := Case{Name: c.Name}
			for _, p := range c.Fields {
				r.Fields = append(r.Fields, Param{p.Name, Sub(p.Type, substitution(t))})
			}
			result = append(result, r)
		}
	}
	return result
}
func function(params []Param, result *Type) *Type {
	return &Type{Kind: "function", ID: "fn", Name: "fn", Params: params, Result: result}
}
func primitive(name string) *Type { return &Type{Name: name, ID: name, Kind: "primitive"} }
func standard(name string, args ...*Type) *Type {
	t := *standardSymbols[name].Type
	t.Args = args
	return &t
}
func std(t *Type, name string) bool { return t != nil && t.ID == "@std/"+name }
func typeKey(t *Type) string {
	var key strings.Builder
	writeTypeKey(&key, t)
	return key.String()
}

// writeTypeKey appends t's key; building nested keys by concatenation would
// copy each inner key once per enclosing level.
func writeTypeKey(key *strings.Builder, t *Type) {
	if t == nil {
		return
	}
	key.WriteString(t.ID)
	if t.Kind == "function" {
		for _, p := range t.Params {
			key.WriteString("[" + p.Name + ":")
			writeTypeKey(key, p.Type)
			key.WriteString("]")
		}
		key.WriteString("[result:")
		writeTypeKey(key, t.Result)
		key.WriteString("]")
	}
	for _, a := range t.Args {
		key.WriteString("[")
		writeTypeKey(key, a)
		key.WriteString("]")
	}
}
func TypeKey(t *Type) string { return typeKey(t) }
func unify(pattern, actual *Type, vars map[string]bool, sub map[string]*Type) bool {
	if pattern == nil || actual == nil {
		return false
	}
	if vars[pattern.ID] {
		if previous := sub[pattern.ID]; previous != nil {
			return Same(previous, actual)
		}
		sub[pattern.ID] = requiredType(actual)
		return true
	}
	if pattern.ID != actual.ID || len(pattern.Args) != len(actual.Args) || len(pattern.Params) != len(actual.Params) {
		return false
	}
	for i := range pattern.Args {
		if !unify(pattern.Args[i], actual.Args[i], vars, sub) {
			return false
		}
	}
	if pattern.Kind == "function" {
		for i, p := range pattern.Params {
			if p.Name != actual.Params[i].Name || !unify(p.Type, actual.Params[i].Type, vars, sub) {
				return false
			}
		}
		return unify(pattern.Result, actual.Result, vars, sub)
	}
	return true
}
func variableSet(types []*Type) map[string]bool {
	result := map[string]bool{}
	for _, t := range types {
		result[t.ID] = true
	}
	return result
}
func formatMismatch(actual, expected *Type) string {
	return fmt.Sprintf("expected %s, found %s", expected, actual)
}

// requiredTypeArguments counts the leading type variables without a default.
func requiredTypeArguments(vars []*Type) int {
	for index, v := range vars {
		if v.Default != nil {
			return index
		}
	}
	return len(vars)
}

// completeTypeArguments fills unresolved (nil) and omitted trailing arguments from
// defaults, in terms of the arguments before them; other nils are left for the
// caller to report.
func completeTypeArguments(vars, args []*Type) []*Type {
	result := append([]*Type(nil), args...)
	sub := map[string]*Type{}
	for index, v := range vars {
		if index >= len(result) {
			result = append(result, nil)
		}
		if result[index] == nil && v.Default != nil {
			result[index] = Sub(v.Default, sub)
		}
		if result[index] != nil {
			sub[v.ID] = result[index]
		}
	}
	return result
}

// withDefaultArguments extends explicit arguments with the defaults of the
// remaining variables, each in terms of the arguments before it.
func withDefaultArguments(vars, args []*Type) []*Type {
	result := append([]*Type(nil), args...)
	sub := map[string]*Type{}
	for index, a := range result {
		sub[vars[index].ID] = a
	}
	for _, v := range vars[len(args):] {
		a := Sub(v.Default, sub)
		sub[v.ID] = a
		result = append(result, a)
	}
	return result
}
