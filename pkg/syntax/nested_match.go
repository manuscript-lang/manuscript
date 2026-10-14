package syntax

// NestedMatches returns matches structurally inside another match, in source
// order. This is syntax information for advisories, not a grammar restriction.
// Helpers have separate trees; inline closures remain inside their enclosing
// expression, as do scrutinees, defaults and interpolations.
func NestedMatches(module *Module) []*Expression {
	var matches []*Expression
	if module == nil {
		return matches
	}
	depth := 0
	visitor := Visitor{
		Expression: func(e *Expression) {
			if e.Kind == KindMatch {
				if depth > 0 {
					matches = append(matches, e)
				}
				depth++
			}
		},
		LeaveExpression: func(e *Expression) {
			if e.Kind == KindMatch {
				depth--
			}
		},
	}
	for _, declaration := range module.Declarations {
		visitor.Walk(declaration)
	}
	return matches
}
