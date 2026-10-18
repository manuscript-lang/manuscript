package tooling

import (
	"fmt"
	"sort"
	"strings"
)

// DiagramASCII renders the static call graph as a plain-text outline: owners
// in ID order, each followed by its distinct callees with a count. The text
// depends only on the inspection, so equal programs print equal bytes.
func DiagramASCII(inspection Inspection) string {
	labels := map[string]string{}
	for _, entity := range inspection.Entities {
		labels[entity.ID] = entity.Span.File + "::" + entity.Name
	}
	label := func(id string) string {
		if name, ok := labels[id]; ok {
			return name
		}
		return id
	}
	type edge struct{ target, kind string }
	edges := map[string]map[edge]int{}
	for _, call := range inspection.Calls {
		if edges[call.Owner] == nil {
			edges[call.Owner] = map[edge]int{}
		}
		edges[call.Owner][edge{label(call.Target), call.Kind}]++
	}
	var b strings.Builder
	b.WriteString("CALL GRAPH\n")
	for _, entity := range inspection.Entities {
		fmt.Fprintf(&b, "%s [%s]\n", label(entity.ID), entity.Kind)
		var list []edge
		for e := range edges[entity.ID] {
			list = append(list, e)
		}
		sort.Slice(list, func(i, j int) bool {
			if list[i].target != list[j].target {
				return list[i].target < list[j].target
			}
			return list[i].kind < list[j].kind
		})
		for _, e := range list {
			count := ""
			if n := edges[entity.ID][e]; n > 1 {
				count = fmt.Sprintf(" x%d", n)
			}
			fmt.Fprintf(&b, "  -> %s (%s)%s\n", e.target, e.kind, count)
		}
	}
	return b.String()
}
