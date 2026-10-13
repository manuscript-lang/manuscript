package msruntime

import (
	"context"
	"testing"
)

func TestPrimitiveSortingCancellationPreservesInput(t *testing.T) {
	for _, operation := range []struct {
		name, typ string
		item      Value
	}{
		{"sorted_int", "Int", int64(2)},
		{"sorted_float", "Float", float64(2)},
		{"sorted_strings", "String", "é"},
	} {
		items := make([]Value, 4096)
		for i := range items {
			items[i] = operation.item
		}
		input := libraryList(operation.typ, items)
		ctx := RootExecution()
		workContext, cancel := context.WithCancel(ctx.Context)
		work := &stringWorkCancellation{Context: workContext, cancel: cancel}
		ctx.Context = work
		failure := recovered(func() {
			libraryFunctions["collections/"+operation.name].Body(ctx, input.Type, []Value{input})
		})
		cancel()
		if _, ok := failure.(cancelled); !ok || work.checks < 2 {
			t.Fatalf("%s lost cancellation: %#v", operation.name, failure)
		}
		if &items[0] != &input.Items[0] || len(input.Items) != len(items) {
			t.Fatal("cancelled sorting replaced input storage")
		}
		for _, item := range input.Items {
			if item != operation.item {
				t.Fatal("cancelled sorting changed input values")
			}
		}
	}
}
