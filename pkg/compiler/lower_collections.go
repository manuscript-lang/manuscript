package compiler

import (
	"go/ast"

	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// These checked native operations neither invoke callbacks nor acquire
// resources. Direct calls can share their runtime implementation without
// constructing a bound Function, resolving labels, or changing Optional storage.
// References to bound methods still use ordinary callable dispatch.
func (g *generator) directCollectionCall(e *syntax.Expression, arguments []syntax.Argument) ast.Expr {
	callee := g.program.Expressions[e.Left]
	if e.Left.Kind != syntax.KindMember || callee == nil || callee.Method == nil || callee.Method.Contract != nil {
		return nil
	}
	switch callee.Method.Native {
	case "collections/at":
		if len(arguments) == 1 {
			// Force even a plain local receiver to be read before the index:
			// a match expression in the index can reassign that local. Go does
			// not otherwise order a variable read before a later function call.
			receiver := sourceAt(e.Left.Left.Pos, g.expression(e.Left.Left))
			return g.locatedOperation(e, runtimeName("ListAt"), ident("ctx"), receiver, g.expression(arguments[0].Value), g.key(g.program.Expressions[e].Type))
		}
	case "length":
		// Collection length reads the receiver's size; it never calls back or fails.
		switch g.program.Expressions[e.Left.Left].Type.ID {
		case "@std/List", "@std/Map", "@std/Set":
			if len(arguments) == 0 {
				return g.locatedOperation(e, runtimeName("CollectionLength"), ident("ctx"), g.expression(e.Left.Left))
			}
		}
	case "byte_length":
		if len(arguments) == 0 && g.program.Expressions[e.Left.Left].Type.ID == "String" {
			return g.locatedOperation(e, runtimeName("StringByteLength"), ident("ctx"), g.expression(e.Left.Left))
		}
	case "optional/unwrap":
		if len(arguments) == 0 {
			return g.locatedOperation(e, runtimeName("OptionalUnwrap"), ident("ctx"), g.expression(e.Left.Left))
		}
	}
	return nil
}
