package msruntime

import (
	"reflect"
	"testing"
)

func TestListFindReturnsVisitedValueAfterMutation(t *testing.T) {
	for _, name := range []string{"find", "find_last", "find_index", "find_last_index"} {
		for _, writer := range []string{"with_value", "set", "without", "remove"} {
			t.Run(name+"/"+writer, func(t *testing.T) {
				ctx := RootExecution()
				defer FinishExecution(ctx)
				reverse := name == "find_last" || name == "find_last_index"
				remove := writer == "without" || writer == "remove"
				target := int32(1)
				if reverse {
					target = 3
					if remove {
						target = 2 // Remove a middle cell so the backing cell changes.
					}
				}
				ref := []int32{1, 2, 3}
				captured := ref
				var expected int32
				wantIndex := -1
				start, end, step := 0, len(captured), 1
				if reverse {
					start, end, step = len(captured)-1, -1, -1
				}
				for i := start; i != end; i += step {
					value := captured[i]
					if value != target {
						continue
					}
					if remove {
						ref = append(ref[:i], ref[i+1:]...)
					} else {
						ref[i] = 9
					}
					expected, wantIndex = value, i
					break
				}
				list := &List{Type: "@std/List[Int]", Items: []Value{int32(1), int32(2), int32(3)}}
				predicate := NewFunction([]string{"value"}, "Bool", func(ctx *Execution, args []Value) Value {
					value := args[0].(int32)
					if value != target {
						return false
					}
					arguments := []Argument{{"index", value - 1}}
					if !remove {
						arguments = append(arguments, Argument{"value", int32(9)})
					}
					if Invoke(ctx, NativeMember(list, writer), arguments) != list {
						t.Fatal("alias lost receiver")
					}
					return true
				})
				found := Invoke(ctx, NativeMember(list, name), []Argument{{"predicate", predicate}}).(Alternative)
				if name == "find_index" || name == "find_last_index" {
					expected = int32(wantIndex)
				}
				if found.Tag != "some" || !reflect.DeepEqual(found.Fields, []Value{expected}) {
					t.Fatalf("returned %v, expected visited value/index %d", found, expected)
				}
				if len(list.Items) != len(ref) {
					t.Fatal("receiver length changed")
				}
				for i, value := range ref {
					if list.Items[i] != value {
						t.Fatal("receiver differs from Go mutation")
					}
				}
			})
		}
	}
}
