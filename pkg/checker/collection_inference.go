package checker

import "github.com/manuscript-lang/manuscript/pkg/syntax"

// Context dependence is syntactic except for name lookup. Retain the lexical
// scope and module so callback probes and checks in other scopes cannot reuse it.
type collectionContext struct {
	scope      *scope
	module     *syntax.Module
	contextual bool
}

type collectionValidity struct {
	scope   *scope
	module  *syntax.Module
	methods int
}

func (c *checker) collectionElement(elements []*syntax.Expression, inferred []*Info, start, stride int, expected *Type) *Type {
	if expected != nil {
		return expected
	}
	for at := start; at < len(elements); at += stride {
		item := elements[at]
		if !c.contextual(item) {
			value := c.expression(item, nil)
			inferred[at] = value
			if expected == nil && value.Type.ID != "Never" {
				expected = value.Type
			}
		}
	}
	if expected == nil {
		// An all-contextual nested collection still has a known outer shape.
		// Let its innermost empty literal own the missing-element diagnostic,
		// then pass that shape to its siblings instead of reporting every level.
		for at := start; at < len(elements); at += stride {
			item := elements[at]
			if item.Kind == syntax.KindList || item.Kind == syntax.KindMap {
				value := c.expression(item, nil)
				inferred[at] = value
				return value.Type
			}
		}
	}
	return expected
}

func (c *checker) collectionExpression(e *syntax.Expression, inferred *Info, expected *Type) *Info {
	if inferred != nil && inferred.Type == expected {
		// The independent pass already checked every child. Keep that evidence
		// when its exact type supplies the context; rebuilding the same nested
		// tree here caused cubic checking. Different contexts still re-infer,
		// including callback labels, generic result evidence and conversions.
		return c.checkExpression(e, inferred, expected)
	}
	return c.expression(e, expected)
}
