package msruntime

import (
	"fmt"
	"reflect"
)

// MaxEqualityDepth bounds how deeply == recurses through nested values (every
// record, alternative, list, set and map level counts), so comparing a very
// deep structure such as a long linked list is a fault instead of Go's
// unrecoverable stack overflow. Each level uses about 1.5 KiB of Go stack.
const MaxEqualityDepth = 250000

type equalityIdentity struct {
	pointer  any
	typ, tag string
}

type equalityPair struct{ left, right equalityIdentity }

type equalityState struct {
	active map[equalityPair]bool
	ctx    *Execution
	scope  TypeScope
}

func equalityID(value Value) (equalityIdentity, bool) {
	switch v := value.(type) {
	case Struct:
		return equalityIdentity{v, v.StructType(), "record"}, true
	case Record:
		return equalityIdentity{reflect.ValueOf(v.Fields).UnsafePointer(), v.Type, "record"}, true
	case *List:
		return equalityIdentity{v, v.Type, "list"}, true
	case *Map:
		return equalityIdentity{v, v.Type, "map"}, true
	case *Set:
		return equalityIdentity{v, v.Type, "set"}, true
	case Alternative:
		return equalityIdentity{reflect.ValueOf(v.Fields).UnsafePointer(), v.Type, v.Tag}, true
	}
	return equalityIdentity{}, false
}

// primitiveEqual compares Int, Float, String, and Bool operands directly. These
// types cannot carry a user Equal implementation, so it needs no scope, cycle
// bookkeeping, or state allocation.
func primitiveEqual(a, b Value) (result, ok bool) {
	switch x := a.(type) {
	case int64:
		if y, same := b.(int64); same {
			return x == y, true
		}
	case string:
		if y, same := b.(string); same {
			return x == y, true
		}
	case bool:
		if y, same := b.(bool); same {
			return x == y, true
		}
	case float64:
		if y, same := b.(float64); same {
			return x == y, true
		}
	}
	return false, false
}

func Equal(a, b Value) bool { return equal(a, b, &equalityState{}) }

func EqualIn(ctx *Execution, a, b Value) bool { return EqualSelected(ctx, a, b, ctx.EqualityScope) }

func EqualSelected(ctx *Execution, a, b Value, scope TypeScope) bool {
	if result, ok := primitiveEqual(a, b); ok {
		return result
	}
	return equal(a, b, &equalityState{ctx: ctx, scope: scope})
}

func Equality(ctx *Execution, operator string, a, b Value, scope TypeScope) Value {
	result := EqualSelected(ctx, a, b, scope)
	if operator == "!=" {
		result = !result
	}
	return result
}

func equal(a, b Value, state *equalityState) bool {
	if result, ok := primitiveEqual(a, b); ok {
		return result
	}
	if view, ok := a.(View); ok {
		a = view.Receiver
		stateCopy := *state
		stateCopy.scope = view.Scope
		state = &stateCopy
	}
	if view, ok := b.(View); ok {
		b = view.Receiver
	}
	if state.ctx != nil {
		if method, ok := implementationFunction(a, "@std/Equal", "equals", state.scope); ok {
			return Invoke(state.ctx, method, []Argument{{"other", ViewOf("@std/Equal", b, state.scope)}}).(bool)
		}
	}
	if left, ok := equalityID(a); ok {
		if right, ok := equalityID(b); ok {
			pair := equalityPair{left, right}
			if state.active[pair] {
				return true
			}
			if state.active == nil {
				state.active = map[equalityPair]bool{}
			}
			if len(state.active) >= MaxEqualityDepth {
				Panic(fmt.Sprintf("equality depth limit exceeded (%d nested values)", MaxEqualityDepth))
			}
			state.active[pair] = true
			defer delete(state.active, pair)
		}
	}
	switch x := a.(type) {
	case libraryBigInt:
		y, ok := b.(libraryBigInt)
		return ok && x.n.Cmp(y.n) == 0
	case libraryTimestamp:
		y, ok := b.(libraryTimestamp)
		return ok && x.t.Equal(y.t)
	case int64:
		y, ok := b.(int64)
		return ok && x == y
	case float64:
		y, ok := b.(float64)
		return ok && x == y
	case string:
		y, ok := b.(string)
		return ok && x == y
	case bool:
		y, ok := b.(bool)
		return ok && x == y
	case Unit:
		_, ok := b.(Unit)
		return ok
	case Decimal:
		y, ok := b.(Decimal)
		return ok && x.Value.Cmp(y.Value) == 0
	case Duration:
		y, ok := b.(Duration)
		return ok && x == y
	case Instant:
		y, ok := b.(Instant)
		if !ok {
			return false
		}
		sameClock(x, y)
		return x.Tick == y.Tick
	case Bytes:
		y, ok := b.(Bytes)
		if !ok || len(x.Items) != len(y.Items) {
			return false
		}
		for i, v := range x.Items {
			if v != y.Items[i] {
				return false
			}
		}
		return true
	case Struct:
		return equal(structRecord(x), structValue(b), state)
	case Record:
		y, ok := b.(Record)
		if !ok || x.Type != y.Type {
			return false
		}
		xf, yf := fieldsSnapshot(x.Fields), fieldsSnapshot(y.Fields)
		if len(xf) != len(yf) {
			return false
		}
		for k, v := range xf {
			if !equal(v, yf[k], state) {
				return false
			}
		}
		return true
	case Alternative:
		y, ok := b.(Alternative)
		return ok && x.Type == y.Type && x.Tag == y.Tag && equalItemsState(x.Fields, y.Fields, state)
	case *List:
		y, ok := b.(*List)
		return ok && equalLists(x, y, state)
	case *Set:
		y, ok := b.(*Set)
		if !ok || x.Type != y.Type || len(x.Items) != len(y.Items) {
			return false
		}
		child := equalityChild(state, 0)
		for _, v := range x.Items {
			if keyedPosition(y, v, child) < 0 {
				return false
			}
		}
		return true
	case *Map:
		y, ok := b.(*Map)
		if !ok || x.Type != y.Type || len(x.Entries) != len(y.Entries) {
			return false
		}
		keys, values := equalityChild(state, 0), equalityChild(state, 1)
		for _, e := range x.Entries {
			at := keyedPosition(y, e.Key, keys)
			if at < 0 || !equal(e.Value, y.Entries[at].Value, values) {
				return false
			}
		}
		return true
	}
	return false
}

// keyedPosition returns the position of the key equal to key in a Set or Map,
// or -1. With an execution it uses the collection's hash index, so comparing
// two collections is linear instead of quadratic; without one (hashing a
// record key needs the execution's equality scope) it scans.
func keyedPosition(c keyed, key Value, state *equalityState) int {
	if state.ctx != nil {
		return lookupKey(keyContext(state.ctx, key, state.scope), c, key)
	}
	for i, n := 0, c.count(); i < n; i++ {
		if equal(c.keyAt(i), key, state) {
			return i
		}
	}
	return -1
}

func equalItemsState(a, b []Value, state *equalityState) bool {
	if len(a) != len(b) {
		return false
	}
	for i, v := range a {
		if !equal(v, b[i], state) {
			return false
		}
	}
	return true
}

func indexOfIn(ctx *Execution, items []Value, value Value) int {
	for i, v := range items {
		if EqualIn(ctx, v, value) {
			return i
		}
	}
	return -1
}

// equalLists is separate from equal so its locals do not enlarge the frame of
// every nested comparison; deep values are bounded by MaxEqualityDepth frames.
func equalLists(x, y *List, state *equalityState) bool {
	if x.Type != y.Type {
		return false
	}
	// Element equality may mutate either outer List. Capture both headers
	// before checking lengths; writes remain visible but growth/shrink and
	// reallocation cannot change the arrays or membership being compared.
	left, right := x.Capture(), y.Capture()
	if left.Len() != right.Len() {
		return false
	}
	if same, handled := equalPrimitiveListRanges(left, right); handled {
		return same
	}
	child := equalityChild(state, 0)
	for i := 0; i < left.Len(); i++ {
		if !equal(left.Get(i), right.Get(i), child) {
			return false
		}
	}
	return true
}

func equalityChild(state *equalityState, index int) *equalityState {
	if index >= len(state.scope.Args) {
		return state
	}
	child := *state
	child.scope = state.scope.Args[index]
	return &child
}
