package checker

import (
	"maps"
	"math/rand"
	"reflect"
	"strconv"
	"testing"
)

// Reachability is an independent oracle for the conservative effect summary:
// each node has every direct effect of every reachable node, and missing
// callees contribute unknown. Include cycles with no effects and with multiple
// effect sources, so propagation must revisit nodes after later changes.
func TestPropagateEffectsMatchesReachability(t *testing.T) {
	random := rand.New(rand.NewSource(7))
	for sample := 0; sample < 100; sample++ {
		nodes := map[string]*effectNode{}
		direct := map[string]map[string]bool{}
		const count = 16
		for i := 0; i < count; i++ {
			name := strconv.Itoa(i)
			node := newEffectNode(nil)
			for _, effect := range []string{"read", "write", "external-call", "unknown", "custom"} {
				if random.Intn(10) == 0 {
					node.add(effect)
				}
			}
			for j := 0; j < count+1; j++ {
				if random.Intn(10) == 0 {
					node.edges[strconv.Itoa(j)] = true
				}
			}
			nodes[name] = node
			direct[name] = maps.Clone(node.effects)
		}
		want := map[string]map[string]bool{}
		for root := range nodes {
			effects := map[string]bool{}
			seen := map[string]bool{}
			var visit func(string)
			visit = func(id string) {
				if seen[id] {
					return
				}
				seen[id] = true
				node := nodes[id]
				if node == nil {
					effects["unknown"] = true
					return
				}
				maps.Copy(effects, direct[id])
				for edge := range node.edges {
					visit(edge)
				}
			}
			visit(root)
			want[root] = effects
		}
		for range 2 {
			propagateEffects(nodes)
			for id, node := range nodes {
				if !reflect.DeepEqual(node.effects, want[id]) {
					t.Fatalf("graph %d, node %s: want %v, got %v", sample, id, want[id], node.effects)
				}
			}
		}
	}
}

func TestPropagateEffectsPureCycle(t *testing.T) {
	left, right := newEffectNode(nil), newEffectNode(nil)
	left.edges["right"] = true
	right.edges["left"] = true
	propagateEffects(map[string]*effectNode{"left": left, "right": right})
	if len(left.effects) != 0 || len(right.effects) != 0 {
		t.Fatal("a pure cycle acquired effects", left.effects, right.effects)
	}
}
