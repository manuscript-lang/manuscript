package checker

import "github.com/manuscript-lang/manuscript/pkg/syntax"

// Resolve before introducing any sibling payload bindings. This is advisory
// evidence only: every non-placeholder name still creates its ordinary binding.
func (c *checker) matchBindingNames(arm *syntax.Arm, fields []Param) {
	conflicts := make([]*Info, len(arm.Names))
	for index, name := range arm.Names {
		if name == "_" || index >= len(fields) || c.scope.binding(name) != nil || c.scope.typ(name) != nil {
			continue
		}
		if symbol := c.names[name]; symbol != nil {
			if symbol.Kind == syntax.KindType {
				conflicts[index] = &Info{Type: symbol.Type, Symbol: symbol}
			}
			continue
		}
		// A nested match can name cases of its scrutinee even when the payload's
		// defining type was not imported (e.g. filesystem().stat's error type).
		payload := fields[index].Type
		if payload != nil && payload.Kind == "alternative" {
			if _, ok := caseOf(payload, name); ok {
				conflicts[index] = &Info{Type: payload, Case: name}
				continue
			}
		}
		// Otherwise retain visible case evidence, omitting the owner when
		// ambiguous. Do not issue resolution errors or choose by map order.
		var owner *Type
		ambiguous := false
		for typeName, symbol := range c.names {
			if symbol.Kind != syntax.KindType || symbol.Type.Kind != "alternative" || c.scope.binding(typeName) != nil || c.scope.typ(typeName) != nil {
				continue
			}
			if _, ok := caseOf(symbol.Type, name); ok {
				if owner != nil && owner.ID != symbol.Type.ID {
					ambiguous = true
					break
				}
				owner = symbol.Type
			}
		}
		if ambiguous {
			conflicts[index] = &Info{Case: name}
		} else if owner != nil {
			conflicts[index] = &Info{Type: owner, Case: name}
		}
	}
	c.ArmNameConflicts[arm] = conflicts
}
