package checker

import "github.com/manuscript-lang/manuscript/pkg/syntax"

// finiteTypeApplications follows declaration dependencies, not expanded field
// layouts. For example, Box[Box[Int]] mentions Box twice but is not a recursive
// declaration. Function and interface signatures still participate in genuine
// recursive generic applications even though values store references.
func (c *checker) finiteTypeApplications() {
	nodes := map[string]applicationNode{}
	types := map[string]*Type{}
	var roots []string
	for _, module := range c.Modules {
		for _, d := range module.Declarations {
			if d.Kind != syntax.KindRecord && d.Kind != "alternative" && d.Kind != syntax.KindInterface {
				continue
			}
			symbol := c.symbols[module.File][d.Name]
			if symbol == nil || symbol.Decl != d {
				continue
			}
			nodes[symbol.Type.ID] = applicationNode{symbol.Variables, d}
			types[symbol.Type.ID] = symbol.Type
			roots = append(roots, symbol.Type.ID)
		}
	}
	edges := map[string][]applicationEdge{}
	names := map[syntax.Position]string{}
	for _, id := range roots {
		var reference func(*Type, syntax.Position)
		reference = func(t *Type, pos syntax.Position) {
			if t == nil {
				return
			}
			if _, exists := nodes[t.ID]; exists {
				edges[id] = append(edges[id], applicationEdge{t.ID, t.Args, pos})
			}
			for _, a := range t.Args {
				reference(a, pos)
			}
			for _, p := range t.Params {
				reference(p.Type, pos)
			}
			reference(t.Result, pos)
		}
		d := nodes[id].decl
		def := types[id].Def
		for i, f := range def.Fields {
			pos := d.Fields[i].Pos
			names[pos] = d.Name + "." + f.Name
			reference(f.Type, pos)
		}
		for i, cs := range def.Cases {
			for j, f := range cs.Fields {
				pos := d.Cases[i].Fields[j].Pos
				names[pos] = d.Name + "." + cs.Name + "." + f.Name
				reference(f.Type, pos)
			}
		}
		for i, op := range def.Operations {
			pos := d.Methods[i].Pos
			names[pos] = d.Name + "." + op.Name
			reference(op.Type, pos)
		}
	}
	reported := map[syntax.Position]bool{}
	// A specialization's reachable subgraph is explored once across all roots,
	// so checking N declarations is linear in the graph rather than N walks.
	visited := map[string]bool{}
	for _, root := range roots {
		active := map[string][]*Type{}
		var visit func(string, []*Type)
		visit = func(id string, args []*Type) {
			// Shared dependencies need checking once for each specialization.
			// Check active cycles at the edge before consulting this cache.
			key := typeKey(&Type{ID: id, Args: args})
			if visited[key] {
				return
			}
			visited[key] = true
			active[id] = args
			defer delete(active, id)
			sub := map[string]*Type{}
			for i, variable := range nodes[id].variables {
				if i < len(args) {
					sub[variable.ID] = args[i]
				}
			}
			for _, edge := range edges[id] {
				next := make([]*Type, len(edge.arguments))
				for i, argument := range edge.arguments {
					next[i] = Sub(argument, sub)
				}
				if previous, exists := active[edge.target]; exists {
					same := len(previous) == len(next)
					for i := 0; same && i < len(previous); i++ {
						same = Same(previous[i], next[i])
					}
					if !same && !reported[edge.pos] {
						reported[edge.pos] = true
						c.error(edge.pos, "type", "recursive generic applications must preserve their parameters in "+names[edge.pos]+"; keep the same type arguments in the same positions along a recursive cycle")
					}
					continue
				}
				visit(edge.target, next)
			}
		}
		visit(root, nodes[root].variables)
	}
}
