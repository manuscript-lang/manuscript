package lower

import (
	"go/ast"
	"go/token"
)

// cacheListItems hoists a list's Items slice out of loops that cannot change it.
//
// Go keeps a slice header in registers, but a field of a heap list is reloaded
// after every store, so indexed numeric loops pay two extra loads per element.
// A loop qualifies when every call in it is a known helper that cannot replace
// a list's Items (indexed get/set, cancellation polls, Int arithmetic and
// conversions) and the list is a variable the loop never assigns. Only calls
// the lowerer already emitted are inspected; any other call, closure, defer or
// go statement leaves the loop unchanged. The out-of-range, negative-index
// and fault paths still run the ordinary helpers on the list itself.
func (g *gen) cacheListItems(body []ast.Stmt) []ast.Stmt {
	if g.options.PreserveBindings || g.options.Locals != nil {
		return body
	}
	return g.cacheItemsIn(body)
}

func (g *gen) cacheItemsIn(stmts []ast.Stmt) []ast.Stmt {
	var out []ast.Stmt
	for _, s := range stmts {
		out = append(out, g.cacheItemsStmt(s)...)
	}
	return out
}

// cacheItemsStmt returns s preceded by any declarations its loop needs.
func (g *gen) cacheItemsStmt(s ast.Stmt) []ast.Stmt {
	switch n := unlabel(s).(type) {
	case *ast.ForStmt:
		pre := g.hoistItems(n)
		n.Body.List = g.cacheItemsIn(n.Body.List)
		return append(pre, s)
	case *ast.RangeStmt:
		pre := g.hoistItems(n)
		n.Body.List = g.cacheItemsIn(n.Body.List)
		return append(pre, s)
	case *ast.BlockStmt:
		n.List = g.cacheItemsIn(n.List)
	case *ast.IfStmt:
		n.Body.List = g.cacheItemsIn(n.Body.List)
		if n.Else != nil {
			if els := g.cacheItemsStmt(n.Else); len(els) == 1 {
				n.Else = els[0]
			} else {
				n.Else = block(els...)
			}
		}
	case *ast.SwitchStmt:
		n.Body.List = g.cacheItemsIn(n.Body.List)
	case *ast.TypeSwitchStmt:
		n.Body.List = g.cacheItemsIn(n.Body.List)
	case *ast.CaseClause:
		n.Body = g.cacheItemsIn(n.Body)
	}
	return []ast.Stmt{s}
}

// itemsRewrite is one indexed get or set of a list variable.
type itemsRewrite struct {
	call *ast.CallExpr
	set  bool
}

// listItemsHelpers are runtime calls that never replace a list's Items.
var listItemsHelpers = map[string]bool{
	"List_Get": true, "List_Set": true, "CheckCancelled": true,
	"IntAdd": true, "IntSubtract": true, "IntMultiply": true, "IntDivide": true, "IntRemainder": true, "IntNegate": true,
	"Int_ToFloat": true, "None": true, "List_GetCached": true, "List_SetCached": true,
}

var listItemsConversions = map[string]bool{
	"int": true, "int64": true, "uint": true, "uint32": true, "uint64": true, "float64": true, "bool": true, "string": true, "len": true,
}

// hoistItems rewrites loop in place and returns the declarations to run first.
func (g *gen) hoistItems(loop ast.Stmt) []ast.Stmt {
	type use struct {
		elem     ast.Expr
		rewrites []itemsRewrite
	}
	uses := map[string]*use{}
	var order []string
	blocked := map[string]bool{}
	discarded := map[*ast.CallExpr]bool{}
	valid := true
	block := func(e ast.Expr) {
		if id, ok := e.(*ast.Ident); ok {
			blocked[id.Name] = true
		}
	}
	ast.Inspect(loop, func(n ast.Node) bool {
		if !valid {
			return false
		}
		switch n := n.(type) {
		case *ast.FuncLit, *ast.GoStmt, *ast.DeferStmt:
			valid = false
		case *ast.ExprStmt:
			if c, ok := n.X.(*ast.CallExpr); ok {
				discarded[c] = true
			}
		case *ast.AssignStmt:
			for _, l := range n.Lhs {
				block(l)
			}
		case *ast.IncDecStmt:
			block(n.X)
		case *ast.RangeStmt:
			if n.Key != nil {
				block(n.Key)
			}
			if n.Value != nil {
				block(n.Value)
			}
		case *ast.ValueSpec:
			for _, name := range n.Names {
				blocked[name.Name] = true
			}
		case *ast.UnaryExpr:
			if n.Op == token.AND {
				block(n.X)
			}
		case *ast.CallExpr:
			name, elem, ok := listItemsCallee(n)
			if !ok {
				valid = false
				return false
			}
			if (name != "List_Get" && name != "List_Set") || len(n.Args) != 4 || elem == nil {
				break
			}
			list, isIdent := n.Args[1].(*ast.Ident)
			if !isIdent {
				break
			}
			if name == "List_Set" && !discarded[n] {
				break
			}
			u := uses[list.Name]
			if u == nil {
				u = &use{elem: elem}
				uses[list.Name] = u
				order = append(order, list.Name)
			}
			u.rewrites = append(u.rewrites, itemsRewrite{call: n, set: name == "List_Set"})
		}
		return true
	})
	if !valid {
		return nil
	}
	var pre []ast.Stmt
	for _, name := range order {
		if blocked[name] {
			continue
		}
		u := uses[name]
		items := g.temp()
		pre = append(pre, define(items, rtCall("ItemsOf", ident(name))))
		for _, r := range u.rewrites {
			replacement := "List_GetCached"
			if r.set {
				replacement = "List_SetCached"
			}
			r.call.Fun = generic(rtName(replacement), u.elem)
			r.call.Args = append([]ast.Expr{ident(items)}, r.call.Args[1:]...)
		}
	}
	return pre
}

// listItemsCallee names a call that cannot replace any list's Items, and the
// element type argument of an explicit runtime instantiation.
func listItemsCallee(c *ast.CallExpr) (name string, elem ast.Expr, ok bool) {
	fun := c.Fun
	if ix, isIndex := fun.(*ast.IndexExpr); isIndex {
		fun, elem = ix.X, ix.Index
	}
	switch f := fun.(type) {
	case *ast.Ident:
		return f.Name, nil, listItemsConversions[f.Name]
	case *ast.SelectorExpr:
		if pkg, isIdent := f.X.(*ast.Ident); isIdent && pkg.Name == "rt" {
			return f.Sel.Name, elem, listItemsHelpers[f.Sel.Name]
		}
	}
	return "", nil, false
}
