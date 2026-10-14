package checker

import "github.com/manuscript-lang/manuscript/pkg/syntax"

// isConstant reports whether a symbol is a module-level `let` constant.
func isConstant(s *Symbol) bool {
	return s != nil && s.Kind == syntax.KindFn && s.Decl != nil && s.Decl.Constant
}

// constantType resolves a constant's type once: its annotation, or the type of
// its initializer. A constant that depends on itself is reported and typed
// <invalid>. The use-site rewrite makes every use evaluate the initializer, so
// constants have no initialization order and hold no shared state.
func (c *checker) constantType(s *Symbol) {
	if s.Type != nil {
		return
	}
	d := s.Decl
	if c.constantsVisiting[s] {
		c.error(d.Pos, "type", "constant "+d.Name+" depends on itself; break the cycle or compute the value in a function")
		s.Type = function(nil, primitive("<invalid>"))
		return
	}
	if c.constantsVisiting == nil {
		c.constantsVisiting = map[*Symbol]bool{}
	}
	c.constantsVisiting[s] = true
	defer delete(c.constantsVisiting, s)
	value := d.Body[0].Value
	if !c.constantExpression(value) {
		s.Type = function(nil, primitive("<invalid>"))
		return
	}
	if d.Result.Name != "" {
		s.Type = function(nil, c.resolve(d.Result, false))
		return
	}
	old := c.scope
	c.scope = newScope(nil)
	info := c.expression(value, nil)
	c.scope = old
	if s.Type == nil {
		s.Type = function(nil, info.Type)
	}
}

// constantExpression accepts literals, operators, collection literals, and
// names of other constants or nullary cases; everything else needs a function.
func (c *checker) constantExpression(e *syntax.Expression) bool {
	if e == nil {
		return true
	}
	ok := true
	switch e.Kind {
	case syntax.KindNumber, syntax.KindBool, syntax.KindUnit, syntax.KindText, syntax.KindList, syntax.KindMap, syntax.KindUnary, syntax.KindBinary:
	case syntax.KindName:
		if s := c.names[e.Text]; s != nil && !isConstant(s) {
			c.error(e.Pos, "type", "a constant can refer only to other constants, but "+e.Text+" is a "+c.symbolDescription(s)+"; compute the value in a function")
			ok = false
		}
	default:
		c.error(e.Pos, "type", "a constant takes literals, operators, collections, and other constants; compute this value in a function")
		ok = false
	}
	if !ok {
		return false
	}
	ok = c.constantExpression(e.Left) && c.constantExpression(e.Right)
	for _, element := range e.Elements {
		ok = ok && c.constantExpression(element)
	}
	for _, part := range e.Parts {
		ok = ok && c.constantExpression(part.Value)
	}
	return ok
}
