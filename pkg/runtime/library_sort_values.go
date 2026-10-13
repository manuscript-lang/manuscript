package msruntime

import (
	"math"
	"sort"
)

func init() {
	for _, operation := range []struct {
		name, element string
		less          func(Value, Value) bool
	}{
		{"sorted_int", "Int", func(left, right Value) bool { return left.(int64) < right.(int64) }},
		{"sorted_float", "Float", func(left, right Value) bool {
			a, b := left.(float64), right.(float64)
			return math.IsNaN(a) && !math.IsNaN(b) || a < b
		}},
		{"sorted_strings", "String", func(left, right Value) bool { return left.(string) < right.(string) }},
	} {
		libraryAdd("collections", operation.name, "List["+operation.element+"]", []LibraryParam{{"values", "List[" + operation.element + "]"}}, func(ctx *Execution, result string, args []Value) Value {
			CheckCancelled(ctx)
			items := Iterate(args[0])
			out := make([]Value, len(items))
			for i, value := range items {
				if i%1024 == 0 {
					CheckCancelled(ctx)
				}
				out[i] = value
			}
			sort.SliceStable(out, func(i, j int) bool {
				CheckCancelled(ctx)
				return operation.less(out[i], out[j])
			})
			CheckCancelled(ctx)
			return &List{Type: result, Items: out}
		})
	}
}
