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
		c.reportConstantCycle(s)
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

// checkConstantCycles reports constants that reach themselves through other
// constants. Annotated constants never need their initializer's type, so
// constantType does not follow them; without this pass `let A: Int = B` and
// `let B: Int = A` would pass the check and recurse until the call-depth limit.
func (c *checker) checkConstantCycles(module *syntax.Module) {
	state := map[*Symbol]int{} // 1 visiting, 2 done
	var visit func(s *Symbol)
	var walk func(e *syntax.Expression)
	walk = func(e *syntax.Expression) {
		if e == nil {
			return
		}
		if e.Kind == syntax.KindName {
			if t := c.names[e.Text]; isConstant(t) && t.Module == module.File {
				visit(t)
			}
		}
		walk(e.Left)
		walk(e.Right)
		for _, element := range e.Elements {
			walk(element)
		}
		for _, part := range e.Parts {
			walk(part.Value)
		}
	}
	visit = func(s *Symbol) {
		switch state[s] {
		case 1:
			c.reportConstantCycle(s)
			return
		case 2:
			return
		}
		state[s] = 1
		walk(s.Decl.Body[0].Value)
		state[s] = 2
	}
	for _, d := range module.Declarations {
		if !d.Constant {
			continue
		}
		if s := c.names[d.Name]; s != nil && s.Decl == d {
			visit(s)
		}
	}
}

func (c *checker) reportConstantCycle(s *Symbol) {
	if c.cycleReported[s] {
		return
	}
	if c.cycleReported == nil {
		c.cycleReported = map[*Symbol]bool{}
	}
	c.cycleReported[s] = true
	c.error(s.Decl.Pos, "type", "constant "+s.Decl.Name+" depends on itself; break the cycle or compute the value in a function")
}
