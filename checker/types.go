// Package checker resolves names and verifies Manuscript's nominal type system.
package checker

import (
	"fmt"
	"github.com/manuscript-lang/manuscript/syntax"
	"strings"
)

type Type struct {
	Name, ID, Kind string
	Args           []*Type
	Params         []Param
	Result         *Type
	Def            *Definition
	Bounds         []*Type
	// Defaults marks omittable parameters on a known source callable.
	// It is erased by explicit function types and generic inference.
	Defaults map[string]bool
}
type Param struct {
	Name string
	Type *Type
}
type Definition struct {
	Symbol     *Symbol
	Kind       string
	Variables  []*Type
	Fields     []Param
	Cases      []Case
	Operations []Param
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
	Write       bool
	Captures    []*Binding
	TypeArgs    []*Type
	// Arguments retains written order with omitted function labels resolved.
	Arguments []syntax.Argument
}
type Flow struct{ FallsThrough bool }
type Program struct {
	Flow             map[*syntax.Statement]Flow
	Scopes           map[*syntax.Expression]ScopeState
	Cleanups         map[*syntax.Statement]*Method
	Effects          map[string][]string
	Modules          []*syntax.Module
	TypeReferences   map[*syntax.Type]*Type
	Symbols          map[string]map[string]*Symbol
	Expressions      map[*syntax.Expression]*Info
	Bindings         map[*syntax.Pattern]*Binding
	LoopBindings     map[*syntax.Statement]*Binding
	ArmBindings      map[*syntax.Arm][]*Binding
	ContractPatterns map[*syntax.Arm]*Type
	Parameters       map[*syntax.Declaration][]*Binding
	LambdaParameters map[*syntax.Expression][]*Binding
	Self             map[*syntax.Declaration]*Binding
	Assignments      map[*syntax.Expression]*Binding
	Methods          []*Method
	Diagnostics      []syntax.Diagnostic
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
	if t == nil {
		return ""
	}
	s := t.ID
	if t.Kind == "function" {
		for _, p := range t.Params {
			s += "[" + p.Name + ":" + typeKey(p.Type) + "]"
		}
		s += "[result:" + typeKey(t.Result) + "]"
	}
	for _, a := range t.Args {
		s += "[" + typeKey(a) + "]"
	}
	return s
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
