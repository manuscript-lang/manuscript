package ast

// Walk traverses the AST using the visitor pattern
func Walk(root Node, visitor Visitor) {
	if root != nil {
		root.Accept(visitor)
	}
}

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

// Inspect is a convenience function for walking the tree with a simple function
func Inspect(root Node, fn func(Node)) {
	Walk(root, NewSimpleVisitor(fn))
}
