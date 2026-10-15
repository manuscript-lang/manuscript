package lower

import (
	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// recursiveDeclarations finds the source functions that can reach themselves,
// which must admit each nested call so the call-depth limit and cancellation
// apply. The graph has an edge for each statically resolved call. Calls the
// program cannot resolve (function values, contract dispatch, native
// operations that take callbacks) go through one shared INDIRECT node, which
// reaches every function used as a value and every contract implementation.
func recursiveDeclarations(program *checker.Program) map[*syntax.Declaration]bool {
	if program == nil {
		return nil
	}
	indirect := &syntax.Declaration{}
	edges := map[*syntax.Declaration]map[*syntax.Declaration]bool{}
	link := func(from, to *syntax.Declaration) {
		if from == nil || to == nil {
			return
		}
		if edges[from] == nil {
			edges[from] = map[*syntax.Declaration]bool{}
		}
		edges[from][to] = true
	}
	var nodes []*syntax.Declaration
	scan := func(d *syntax.Declaration) {
		nodes = append(nodes, d)
		callees := map[*syntax.Expression]bool{}
		syntax.Visitor{Expression: func(e *syntax.Expression) {
			if e.Kind == syntax.KindCall && e.Left != nil {
				callees[e.Left] = true
			}
			info := program.Info(e)
			if info == nil {
				return
			}
			switch {
			case e.Kind == syntax.KindCall:
				switch {
				case info.Constructor != nil:
				case info.Symbol != nil && info.Symbol.Native == "":
					link(d, info.Symbol.Decl)
				case info.Symbol != nil:
					link(d, indirect)
				case info.Method != nil && info.Method.Native == "" && info.Method.Decl != nil:
					link(d, info.Method.Decl)
				default:
					link(d, indirect)
				}
			case callees[e]:
			case info.Symbol != nil && info.Symbol.Decl != nil && info.Symbol.Native == "" && e.Kind != syntax.KindCall:
				link(indirect, info.Symbol.Decl)
			case info.Method != nil && info.Method.Decl != nil && info.Method.Native == "":
				link(indirect, info.Method.Decl)
			}
		}}.Walk(d)
	}
	for _, module := range program.Modules {
		for _, d := range module.Declarations {
			if d.Kind == syntax.KindFn || d.Kind == syntax.KindTest {
				scan(d)
			}
			for _, method := range d.Methods {
				scan(method)
			}
		}
	}
	for _, m := range program.Methods {
		if m.Contract != nil && m.Native == "" && m.Decl != nil {
			link(indirect, m.Decl)
		}
	}
	return cyclic(append(nodes, indirect), edges)
}

// cyclic returns the nodes on a cycle: members of a strongly connected
// component of more than one node, or with a self edge.
func cyclic(nodes []*syntax.Declaration, edges map[*syntax.Declaration]map[*syntax.Declaration]bool) map[*syntax.Declaration]bool {
	index := map[*syntax.Declaration]int{}
	low := map[*syntax.Declaration]int{}
	on := map[*syntax.Declaration]bool{}
	var stack []*syntax.Declaration
	out := map[*syntax.Declaration]bool{}
	next := 0
	var visit func(v *syntax.Declaration)
	visit = func(v *syntax.Declaration) {
		next++
		index[v], low[v] = next, next
		stack = append(stack, v)
		on[v] = true
		for w := range edges[v] {
			if index[w] == 0 {
				visit(w)
				low[v] = min(low[v], low[w])
			} else if on[w] {
				low[v] = min(low[v], index[w])
			}
		}
		if low[v] != index[v] {
			return
		}
		var component []*syntax.Declaration
		for {
			w := stack[len(stack)-1]
			stack = stack[:len(stack)-1]
			on[w] = false
			component = append(component, w)
			if w == v {
				break
			}
		}
		if len(component) > 1 || edges[v][v] {
			for _, w := range component {
				out[w] = true
			}
		}
	}
	for _, v := range nodes {
		if index[v] == 0 {
			visit(v)
		}
	}
	return out
}
