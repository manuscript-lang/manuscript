package msruntime

import (
	"fmt"
	"math"
	"sync/atomic"
	"testing"
)

var listEqualityReviewIDs atomic.Uint64

// The old slice equality captured both headers. This oracle uses ordinary Go
// slices and captures each pair before the element's equality callback runs.
func TestListEqualityCapturesBothHeadersBeforeCallbacks(t *testing.T) {
	for _, side := range []string{"left", "right"} {
		for _, mutation := range []string{"shrink", "shrink_mismatch", "append", "append_write", "grow_write", "overwrite"} {
			t.Run(side+"/"+mutation, func(t *testing.T) {
				leftIDs, rightIDs := []int64{1, 2, 3}, []int64{1, 2, 3}
				if mutation == "shrink_mismatch" {
					rightIDs[2] = 99
				}
				capacity := 3
				if mutation == "append" || mutation == "append_write" {
					capacity = 8
				}
				refLeft := make([]int64, 3, capacity)
				copy(refLeft, leftIDs)
				refRight := make([]int64, 3, capacity)
				copy(refRight, rightIDs)
				capturedLeft, capturedRight := refLeft, refRight
				refTarget := &refLeft
				if side == "right" {
					refTarget = &refRight
				}
				want, wantCalls := true, 0
				for i := range capturedLeft {
					left, right := capturedLeft[i], capturedRight[i]
					wantCalls++
					if wantCalls == 1 {
						switch mutation {
						case "shrink", "shrink_mismatch":
							*refTarget = (*refTarget)[:0]
						case "append":
							*refTarget = append(*refTarget, 7)
						case "append_write":
							*refTarget = append(*refTarget, 7)
							(*refTarget)[1] = 77
						case "grow_write":
							for range 100 {
								*refTarget = append(*refTarget, 7)
							}
							(*refTarget)[1] = 77
						case "overwrite":
							(*refTarget)[1] = 77
						}
					}
					if left != right {
						want = false
						break
					}
				}

				typ := fmt.Sprintf("ReviewListEqual/%s/%s/%d", side, mutation, listEqualityReviewIDs.Add(1))
				item := func(id int64) Value { return Record{Type: typ, Fields: map[string]Value{"id": id}} }
				build := func(ids []int64) *List {
					items := make([]Value, 3, capacity)
					for i, id := range ids {
						items[i] = item(id)
					}
					return &List{Type: "@std/List[" + typ + "]", Items: items}
				}
				left, right := build(leftIDs), build(rightIDs)
				target := left
				if side == "right" {
					target = right
				}
				ctx := RootExecution()
				defer FinishExecution(ctx)
				calls := 0
				Register(Implementation{Receiver: typ, Contract: "@std/Equal", Name: "equals", Build: func(receiver Value, _ map[string]string, _ map[string]TypeScope) Function {
					return NewSourceFunction([]string{"other"}, "Bool", "equality-review.ms:1:1", func(ctx *Execution, args []Value) Value {
						calls++
						if calls == 1 {
							switch mutation {
							case "shrink", "shrink_mismatch":
								spliceList(target, 0, target.Len(), newList(target.Type))
							case "append":
								ListAppend(ctx, target, item(7))
							case "append_write":
								ListAppend(ctx, target, item(7))
								target.Set(1, item(77))
							case "grow_write":
								for range 100 {
									ListAppend(ctx, target, item(7))
								}
								target.Set(1, item(77))
							case "overwrite":
								target.Set(1, item(77))
							}
						}
						return receiver.(Record).Fields["id"] == ContractReceiver(args[0]).(Record).Fields["id"]
					})
				}})
				var got bool
				var failure any
				func() { defer func() { failure = recover() }(); got = EqualIn(ctx, left, right) }()
				if failure != nil {
					t.Fatalf("captured equality panicked: %v", failure)
				}
				if got != want || calls != wantCalls {
					t.Fatalf("equality/calls=%v/%d, Go oracle=%v/%d", got, calls, want, wantCalls)
				}
				if left.Len() != len(refLeft) || right.Len() != len(refRight) {
					t.Fatal("mutation lost receiver header")
				}
				for i, id := range refLeft {
					if left.Get(i).(Record).Fields["id"] != id {
						t.Fatal("left receiver differs from Go")
					}
				}
				for i, id := range refRight {
					if right.Get(i).(Record).Fields["id"] != id {
						t.Fatal("right receiver differs from Go")
					}
				}
			})
		}
	}
}

func TestPrimitiveListEqualityAllocationGrowth(t *testing.T) {
	ctx := RootExecution()
	defer FinishExecution(ctx)
	values := make([]int64, 4096)
	for i := range values {
		values[i] = int64(i + 10000)
	}
	short := NewIntList("@std/List[Int]", values[:1])
	shortCopy := Clone(short).(*List)
	long := NewIntList(short.Type, values)
	longCopy := Clone(long).(*List)
	measure := func(left, right *List) float64 {
		return testing.AllocsPerRun(100, func() {
			if !EqualIn(ctx, left, right) {
				t.Fatal("different primitive values")
			}
		})
	}
	if small, large := measure(short, shortCopy), measure(long, longCopy); small != large {
		t.Fatalf("equality allocations grow with cells: 1=%g,4096=%g", small, large)
	}
	longCopy.Set(4095, int64(99))
	if EqualIn(ctx, long, longCopy) {
		t.Fatal("mismatched tail skipped")
	}
	if EqualIn(ctx, NewFloatList("@std/List[Float]", []float64{math.NaN()}), NewFloatList("@std/List[Float]", []float64{math.NaN()})) {
		t.Fatal("NaN list elements became equal")
	}
	if !EqualIn(ctx, NewFloatList("@std/List[Float]", []float64{math.Copysign(0, -1)}), NewFloatList("@std/List[Float]", []float64{0})) {
		t.Fatal("signed zeros became unequal")
	}
}
