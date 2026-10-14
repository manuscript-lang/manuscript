package msruntime

import (
	"math"
	"math/rand"
	"strings"
	"sync/atomic"
	"testing"
)

func pointKey(x, y int64) Value {
	return Record{"Point", map[string]Value{"x": x, "y": y}}
}

// A reference model: the linear scan the index replaces.
func scanFind(ctx *Execution, keys []Value, key Value) int {
	return indexOfIn(ctx, keys, key)
}

func TestMapIndexMatchesLinearScan(t *testing.T) {
	ctx := RootExecution()
	rng := rand.New(rand.NewSource(1))
	m := &Map{Type: "@std/Map[@std/Equal][Int]"}
	var model []Value
	keyFor := func() Value {
		switch rng.Intn(4) {
		case 0:
			return int64(rng.Intn(40))
		case 1:
			return string(rune('a' + rng.Intn(30)))
		case 2:
			return pointKey(int64(rng.Intn(6)), int64(rng.Intn(6)))
		}
		return Alternative{Type: "Shape", Tag: "dot", Fields: []Value{int64(rng.Intn(10))}}
	}
	for step := 0; step < 4000; step++ {
		key := keyFor()
		want := scanFind(ctx, model, key)
		if got := m.find(ctx, key); got != want {
			t.Fatalf("step %d: find(%v) = %d, want %d", step, key, got, want)
		}
		if rng.Intn(3) == 0 && want >= 0 {
			m.removeAt(ctx, want)
			model = append(model[:want], model[want+1:]...)
			continue
		}
		if want < 0 {
			model = append(model, key)
		}
		m.put(ctx, key, int64(step))
		if len(m.Entries) != len(model) {
			t.Fatalf("step %d: %d entries, model has %d", step, len(m.Entries), len(model))
		}
	}
	for i, key := range model {
		if !Equal(m.Entries[i].Key, key) {
			t.Fatalf("insertion order lost at %d", i)
		}
	}
}

func TestSetIndexSurvivesDirectEdits(t *testing.T) {
	ctx := RootExecution()
	s := &Set{Type: "@std/Set[Int]"}
	for i := int64(0); i < 100; i++ {
		s.add(ctx, i)
	}
	if s.add(ctx, int64(50)) {
		t.Fatal("duplicate added")
	}
	s.Items = nil // library code assigns directly
	if s.find(ctx, int64(50)) >= 0 {
		t.Fatal("cleared set still finds 50")
	}
	s.Items = append(s.Items, "x", "y") // and appends directly
	if s.find(ctx, "y") != 1 {
		t.Fatalf("find after direct append = %d", s.find(ctx, "y"))
	}
	s.removeAt(ctx, 0)
	if s.find(ctx, "x") >= 0 || s.find(ctx, "y") != 0 {
		t.Fatal("removal did not shift positions")
	}
	clone := Clone(s).(*Set)
	clone.add(ctx, "z")
	if s.find(ctx, "z") >= 0 || clone.find(ctx, "z") < 0 {
		t.Fatal("clone shares index with original")
	}
}

func TestUnhashableKeyIsAnInvariantViolation(t *testing.T) {
	ctx := RootExecution()
	s := &Set{Type: "@std/Set[@std/List[Int]]"}
	defer func() {
		fault, ok := recover().(Fault)
		if !ok || !strings.Contains(fault.Message, "not Hashable") {
			t.Fatalf("expected a not-Hashable fault, got %v", fault)
		}
	}()
	s.add(ctx, &List{Type: "@std/List[Int]", Items: []Value{int64(1)}})
}

func TestDocumentedKeyMutationProtocol(t *testing.T) {
	ctx := RootExecution()
	m := &Map{Type: "@std/Map[Point][String]"}
	p := pointKey(1, 2).(Record)
	m.put(ctx, p, "a")
	// Remove before mutating a stored key, then reinsert it.
	m.removeAt(ctx, m.find(ctx, p))
	p.Fields["x"] = int64(9)
	m.put(ctx, p, "a")
	if m.find(ctx, pointKey(9, 2)) < 0 || m.find(ctx, pointKey(1, 2)) >= 0 {
		t.Fatal("reinserted key not found by its new value")
	}
	// A clone is independent of later mutation of the original.
	q := pointKey(3, 4).(Record)
	m.put(ctx, Clone(q), "b")
	q.Fields["x"] = int64(7)
	if m.find(ctx, pointKey(3, 4)) < 0 {
		t.Fatal("cloned key changed with the original")
	}
}

var customHashCalls atomic.Int64

func init() {
	equals := func(receiver Value, _ map[string]string, _ map[string]TypeScope) Function {
		return NewFunction([]string{"other"}, "Bool", func(_ *Execution, args []Value) Value {
			return receiver.(Record).Fields["id"] == ContractReceiver(args[0]).(Record).Fields["id"]
		})
	}
	Register(Implementation{Receiver: "CustomKey", Contract: "@std/Equal", Name: "equals", Build: equals})
	Register(Implementation{Receiver: "CustomKey", Contract: "@std/Hashable", Name: "hash", Build: func(receiver Value, _ map[string]string, _ map[string]TypeScope) Function {
		return NewFunction(nil, "Int", func(*Execution, []Value) Value {
			customHashCalls.Add(1)
			return receiver.(Record).Fields["id"]
		})
	}})
}

func customKey(id int64, label string) Value {
	return Record{"CustomKey", map[string]Value{"id": id, "label": label}}
}

func TestCustomHashableIsUsedForLookup(t *testing.T) {
	ctx := RootExecution()
	before := customHashCalls.Load()
	s := &Set{Type: "@std/Set[CustomKey]"}
	s.add(ctx, customKey(1, "first"))
	if s.add(ctx, customKey(1, "other label")) {
		t.Fatal("keys equal by id were stored twice")
	}
	if !s.add(ctx, customKey(2, "second")) || s.find(ctx, customKey(2, "x")) != 1 {
		t.Fatal("distinct id not stored or found")
	}
	if customHashCalls.Load() == before {
		t.Fatal("custom hash was never called")
	}
}

func TestPrimitiveEquality(t *testing.T) {
	ctx := RootExecution()
	nan := math.NaN()
	negativeZero := math.Copysign(0, -1)
	cases := []struct {
		a, b Value
		want bool
	}{
		{int64(1), int64(1), true}, {int64(1), int64(2), false}, {int64(1), 1.0, false},
		{"a", "a", true}, {"a", "b", false}, {true, true, true}, {true, false, false},
		{nan, nan, false}, {0.0, negativeZero, true}, {1.5, 1.5, true},
	}
	for _, c := range cases {
		if got := EqualIn(ctx, c.a, c.b); got != c.want {
			t.Errorf("EqualIn(%v, %v) = %v, want %v", c.a, c.b, got, c.want)
		}
	}
}

// Removing the last remaining key must not leave its stale position behind:
// a later insert at position 0 would otherwise alias both keys to one slot.
func TestIndexForgetsKeysRemovedDownToEmpty(t *testing.T) {
	ctx := RootExecution()
	for _, pair := range [][2]Value{
		{"cap", "pen"},
		{int64(1), int64(2)},
		{pointKey(1, 1), pointKey(2, 2)},
	} {
		first, second := pair[0], pair[1]
		m := &Map{Type: "@std/Map[@std/Equal][Int]"}
		m.put(ctx, first, int64(1))
		m.removeAt(ctx, m.find(ctx, first))
		m.put(ctx, second, int64(2))
		m.put(ctx, first, int64(3))
		if len(m.Entries) != 2 {
			t.Fatalf("map %v/%v: %d entries, want 2", first, second, len(m.Entries))
		}
		if i := m.find(ctx, second); i != 0 || m.Entries[i].Value != int64(2) {
			t.Fatalf("map %v/%v: second found at %d", first, second, i)
		}
		if i := m.find(ctx, first); i != 1 || m.Entries[i].Value != int64(3) {
			t.Fatalf("map %v/%v: first found at %d", first, second, i)
		}

		s := &Set{Type: "@std/Set[@std/Equal]"}
		s.add(ctx, first)
		s.removeAt(ctx, s.find(ctx, first))
		s.add(ctx, second)
		s.add(ctx, first)
		if len(s.Items) != 2 || s.find(ctx, second) != 0 || s.find(ctx, first) != 1 {
			t.Fatalf("set %v/%v: items %v", first, second, s.Items)
		}
	}
}
