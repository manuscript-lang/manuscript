package checker

import "github.com/manuscript-lang/manuscript/pkg/syntax"

type applicationEdge struct {
	target    string
	arguments []*Type
	pos       syntax.Position
}
type applicationNode struct {
	variables []*Type
	decl      *syntax.Declaration
}

func (c *checker) finiteApplications() {
	nodes := map[string]applicationNode{}
	for _, module := range c.Modules {
		for _, d := range module.Declarations {
			if d.Kind == syntax.KindFn || d.Kind == syntax.KindRecord {
				s := c.symbols[module.File][d.Name]
				if len(s.Variables) > 0 {
					nodes[s.ID] = applicationNode{s.Variables, d}
				}
			}
		}
	}
	methods := map[string]*Method{}
	for _, m := range c.Methods {
		methods[m.ID] = m
		if len(m.Variables) > 0 {
			nodes[m.ID] = applicationNode{m.Variables, m.Decl}
		}
	}
	edges := map[string][]applicationEdge{}
	for id, node := range nodes {
		syntax.Visitor{Expression: func(e *syntax.Expression) {
			info := infoOf(e)
			if info == nil {
				return
			}
			if info.Symbol != nil && nodes[info.Symbol.ID].decl != nil && len(info.TypeArgs) > 0 {
				edges[id] = append(edges[id], applicationEdge{info.Symbol.ID, info.TypeArgs, e.Pos})
			}
			if e.Kind == syntax.KindCall && info.Constructor != nil && info.Constructor.Def != nil {
				s := info.Constructor.Def.Symbol
				if s != nil && nodes[s.ID].decl != nil && len(info.Constructor.Args) > 0 {
					edges[id] = append(edges[id], applicationEdge{s.ID, info.Constructor.Args, e.Pos})
				}
			}
			if info.Method != nil && info.Method.ID != "" && nodes[info.Method.ID].decl != nil {
				m := methods[info.Method.ID]
				sub := map[string]*Type{}
				if unify(m.Receiver, info.Method.Receiver, variableSet(m.Variables), sub) {
					var args []*Type
					for _, v := range m.Variables {
						args = append(args, sub[v.ID])
					}
					edges[id] = append(edges[id], applicationEdge{m.ID, args, e.Pos})
				}
			}
		}}.Walk(node.decl)
	}
	for root, node := range nodes {
		active := map[string][]*Type{}
		var visit func(string, []*Type)
		visit = func(id string, args []*Type) {
			if previous := active[id]; previous != nil {
				return
			}
			active[id] = args
			defer delete(active, id)
			sub := map[string]*Type{}
			for i, v := range nodes[id].variables {
				if i < len(args) {
					sub[v.ID] = args[i]
				}
			}
			for _, edge := range edges[id] {
				var next []*Type
				for _, a := range edge.arguments {
					next = append(next, Sub(a, sub))
				}
				if previous := active[edge.target]; previous != nil {
					equal := len(previous) == len(next)
					if equal {
						for i, a := range previous {
							if !Same(a, next[i]) {
								equal = false
								break
							}
						}
					}
					if !equal {
						c.error(edge.pos, "type", "recursive generic applications must preserve their parameters; a type may refer to itself only with the same type arguments (e.g. List[Node[T]] inside Node[T])")
					}
					continue
				}
				visit(edge.target, next)
			}
		}
		visit(root, node.variables)
	}
}
