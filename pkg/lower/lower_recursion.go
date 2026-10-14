package lower

import (
	"go/ast"
	"go/token"

	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// markCounted flags the direct functions that lie on a cycle of direct calls.
// Only they count call depth: any other cycle passes through a dynamic entry
// (NewSourceFunction, NewDirectFunction, a method table entry), which counts.
func (g *generator) markCounted() {
	type node struct {
		direct *directFunction
		decl   *syntax.Declaration
		edges  []*directFunction
	}
	nodes := map[*directFunction]*node{}
	var order []*node
	add := func(direct *directFunction, decl *syntax.Declaration) {
		n := &node{direct: direct, decl: decl}
		nodes[direct] = n
		order = append(order, n)
	}
	for s, direct := range g.direct {
		add(direct, s.Decl)
	}
	for _, m := range g.program.Methods {
		if direct := g.directMethods[m.ID]; direct != nil {
			add(direct, m.Decl)
		}
	}
	for _, n := range order {
		syntax.Visitor{Expression: func(e *syntax.Expression) {
			if e.Kind == syntax.KindMember {
				if info := g.program.Info(e); info != nil && info.Method != nil && info.Method.Accessor {
					if direct := g.directMethods[info.Method.ID]; direct != nil {
						n.edges = append(n.edges, direct)
					}
				}
				return
			}
			if e.Kind != syntax.KindCall {
				return
			}
			info := g.program.Info(e)
			if info == nil {
				return
			}
			if info.Symbol != nil && g.direct[info.Symbol] != nil {
				n.edges = append(n.edges, g.direct[info.Symbol])
			}
			if e.Left != nil && e.Left.Kind == syntax.KindMember {
				if callee := g.program.Info(e.Left); callee != nil && callee.Method != nil && !callee.Method.Accessor && g.directMethods[callee.Method.ID] != nil {
					n.edges = append(n.edges, g.directMethods[callee.Method.ID])
				}
			}
		}}.Callable(n.decl.Params, n.decl.Body)
	}
	// Tarjan's strongly connected components.
	index := map[*node]int{}
	low := map[*node]int{}
	onStack := map[*node]bool{}
	var stack []*node
	next := 0
	var connect func(n *node)
	connect = func(n *node) {
		next++
		index[n], low[n] = next, next
		stack = append(stack, n)
		onStack[n] = true
		for _, edge := range n.edges {
			m := nodes[edge]
			if index[m] == 0 {
				connect(m)
				low[n] = min(low[n], low[m])
			} else if onStack[m] {
				low[n] = min(low[n], index[m])
			}
		}
		if low[n] != index[n] {
			return
		}
		var component []*node
		for {
			m := stack[len(stack)-1]
			stack = stack[:len(stack)-1]
			onStack[m] = false
			component = append(component, m)
			if m == n {
				break
			}
		}
		recursive := len(component) > 1
		for _, edge := range n.edges {
			recursive = recursive || nodes[edge] == n
		}
		if recursive {
			for _, m := range component {
				m.direct.counted = true
			}
		}
	}
	for _, n := range order {
		if index[n] == 0 {
			connect(n)
		}
	}
}

// exitOnReturn makes every return of a counted direct function leave its
// depth first. It does not enter nested function literals, which return to
// their own callers.
func exitOnReturn(body []ast.Stmt) []ast.Stmt {
	out := make([]ast.Stmt, len(body))
	for i, s := range body {
		out[i] = exitStatement(s)
	}
	return out
}

func exitStatement(s ast.Stmt) ast.Stmt {
	switch s := s.(type) {
	case *ast.ReturnStmt:
		if len(s.Results) == 1 {
			return &ast.BlockStmt{List: []ast.Stmt{
				assign(ident("directResult"), token.ASSIGN, s.Results[0]),
				evaluated(runtimeCall("Exit", ident("ctx"))),
				&ast.ReturnStmt{},
			}}
		}
	case *ast.BlockStmt:
		s.List = exitOnReturn(s.List)
	case *ast.IfStmt:
		s.Body = exitStatement(s.Body).(*ast.BlockStmt)
		if s.Else != nil {
			s.Else = exitStatement(s.Else)
		}
	case *ast.ForStmt:
		s.Body = exitStatement(s.Body).(*ast.BlockStmt)
	case *ast.RangeStmt:
		s.Body = exitStatement(s.Body).(*ast.BlockStmt)
	case *ast.LabeledStmt:
		s.Stmt = exitStatement(s.Stmt)
	case *ast.SwitchStmt:
		s.Body = exitStatement(s.Body).(*ast.BlockStmt)
	case *ast.TypeSwitchStmt:
		s.Body = exitStatement(s.Body).(*ast.BlockStmt)
	case *ast.CaseClause:
		s.Body = exitOnReturn(s.Body)
	}
	return s
}
