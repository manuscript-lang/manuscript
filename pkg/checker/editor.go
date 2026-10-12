package checker

import (
	"github.com/manuscript-lang/manuscript/pkg/syntax"
	"sort"
)

// CheckOptions enables targeted editor queries without retaining every lexical scope.
type CheckOptions struct{ ScopeMarker string }

// ScopeState is the visible environment at a requested expression, with shadowing resolved.
type ScopeState struct {
	Bindings map[string]*Binding
	Types    map[string]*Type
	Symbols  map[string]*Symbol
}

func (c *checker) captureScope(e *syntax.Expression) {
	if e == nil || c.scopeMarker == "" || e.Text != c.scopeMarker {
		return
	}
	state := ScopeState{map[string]*Binding{}, map[string]*Type{}, map[string]*Symbol{}}
	hidden := map[string]bool{}
	for s := c.scope; s != nil; s = s.parent {
		for name, b := range s.bindings {
			if !hidden[name] {
				state.Bindings[name] = b
				hidden[name] = true
			}
		}
		for name, t := range s.types {
			if !hidden[name] {
				state.Types[name] = t
				hidden[name] = true
			}
		}
	}
	for name, s := range c.names {
		if !hidden[name] {
			state.Symbols[name] = s
		}
	}
	c.Scopes[e] = state
}

// Member queries use the same resolution and generic-bound rules as calls.
type Member struct {
	Name, Kind  string
	Type        *Type
	Declaration *syntax.Declaration
}

// Members includes local extensions only when their module is supplied.
func Members(program *Program, receiver *Type, module ...string) []Member {
	result := []Member{}
	if program == nil || receiver == nil {
		return result
	}
	c := &checker{Program: program}
	if len(module) > 0 {
		c.module = &syntax.Module{File: module[0]}
	}
	candidates := map[string]bool{"toString": true}
	if nativeMethod(receiver, "clone") != nil {
		candidates["clone"] = true
	}
	var collect func(*Type)
	collect = func(t *Type) {
		if t == nil {
			return
		}
		if t.Def != nil {
			for _, op := range t.Def.Operations {
				candidates[op.Name] = true
			}
		}
		for _, bound := range t.Bounds {
			collect(bound)
		}
	}
	collect(receiver)
	for _, m := range program.Methods {
		if m.Decl != nil {
			candidates[m.Decl.Name] = true
		}
	}
	collect(intrinsicOperations[receiver.ID])
	fields := map[string]bool{}
	if receiver.Kind == syntax.KindRecord {
		for _, field := range Fields(receiver) {
			if field.Name == "toString" {
				continue
			}
			result = append(result, Member{field.Name, "field", field.Type, nil})
			fields[field.Name] = true
		}
	}
	if receiver.ID == "Int" {
		for _, name := range []string{"seconds", "milliseconds", "minutes"} {
			result = append(result, Member{name, "field", standard("Duration"), nil})
		}
	}
	for name := range candidates {
		if fields[name] {
			continue
		}
		methods := c.methods(receiver, name)
		if len(methods) == 1 {
			m := methods[0]
			result = append(result, Member{name, "method", m.Type, m.Decl})
		}
	}
	sort.Slice(result, func(i, j int) bool { return result[i].Name < result[j].Name })
	return result
}

// StandardExportInventory exposes declarations for import completion without introducing ambient names.
func StandardExportInventory() map[string][]*Symbol {
	result := map[string][]*Symbol{}
	for path, exports := range standardModules {
		for _, symbol := range exports {
			if symbol.Export {
				result[path] = append(result[path], symbol)
			}
		}
		sort.Slice(result[path], func(i, j int) bool { return result[path][i].Name < result[path][j].Name })
	}
	return result
}
