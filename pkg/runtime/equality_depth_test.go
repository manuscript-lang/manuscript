package msruntime

import (
	"strings"
	"testing"
)

// linkedValues builds Optional-linked records n deep, like a long linked list.
func linkedValues(n int) Value {
	var next Value = Alternative{Type: "@std/Optional[Node]", Tag: "none"}
	for i := 0; i < n; i++ {
		node := Record{"Node", map[string]Value{"value": int64(i), "next": next}}
		next = Alternative{Type: "@std/Optional[Node]", Tag: "some", Fields: []Value{node}}
	}
	return next
}

func TestEqualityOfDeepValuesFaultsInsteadOfOverflowingTheStack(t *testing.T) {
	// Two levels (alternative and record) per node.
	deep := MaxEqualityDepth/2 + 10
	a, b := linkedValues(deep), linkedValues(deep)
	defer func() {
		fault, ok := recover().(Fault)
		if !ok || !strings.Contains(fault.Message, "equality depth limit exceeded") {
			t.Fatalf("expected an equality depth fault, got %v", fault)
		}
	}()
	Equal(a, b)
	t.Fatal("deep equality did not fault")
}

func TestEqualityBelowTheDepthLimitStillCompares(t *testing.T) {
	const nodes = 20000
	if !Equal(linkedValues(nodes), linkedValues(nodes)) {
		t.Fatal("equal chains compared unequal")
	}
	last := linkedValues(nodes).(Alternative).Fields[0].(Record)
	last.Fields["value"] = int64(-1)
	if Equal(linkedValues(nodes), Alternative{Type: "@std/Optional[Node]", Tag: "some", Fields: []Value{last}}) {
		t.Fatal("different chains compared equal")
	}
}
