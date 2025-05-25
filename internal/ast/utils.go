package ast

// SimpleVisitor is a helper visitor that calls a function on each node
type SimpleVisitor struct {
	Fn func(Node)
}

func (v *SimpleVisitor) Visit(node Node) Visitor {
	v.Fn(node)
	return v
}

// NewSimpleVisitor creates a visitor that calls fn on each node
func NewSimpleVisitor(fn func(Node)) *SimpleVisitor {
	return &SimpleVisitor{Fn: fn}
}
