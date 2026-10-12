package msruntime

import "testing"

func TestPassingAnExistingErrorViewDoesNotAllocate(t *testing.T) {
	cause := Record{"ReadError", map[string]Value{"attempt": int64(1)}}
	original := ViewOf("@std/Error", cause, TypeScope{Module: "first.ms"})
	var result Value
	allocations := testing.AllocsPerRun(100, func() {
		result = ViewOf("@std/Error", original, TypeScope{Module: "second.ms"})
	})
	if allocations != 0 || result.(View).Scope.Module != "first.ms" {
		t.Fatalf("repeated Error boundary allocated or changed dispatch: %v allocations", allocations)
	}
	SetField(ContractReceiver(result), "attempt", int64(2))
	if Field(cause, "attempt") != int64(2) {
		t.Fatal("repeated Error boundary copied the original error")
	}
}

func TestErrorResultRetainsOriginalPayloadStorage(t *testing.T) {
	cause := Record{"ReadError", map[string]Value{"attempt": int64(1)}}
	for _, tag := range []string{"ok", "error"} {
		t.Run(tag, func(t *testing.T) {
			original := Alternative{"@std/Result[ReadError][ReadError]", tag, []Value{cause}}
			result := ErrorResult(original, "@std/Result[ReadError][@std/Error]").(Alternative)
			if result.Type != "@std/Result[ReadError][@std/Error]" || result.Tag != tag || &result.Fields[0] != &original.Fields[0] {
				t.Fatal("Error boundary replaced the result payload storage")
			}
			SetField(result.Fields[0], "attempt", int64(2))
			if Field(cause, "attempt") != int64(2) {
				t.Fatal("Error boundary copied the concrete value")
			}
		})
	}
}

func TestScopedErrorResultDoesNotChangeOriginalResult(t *testing.T) {
	cause := Record{"ReadError", map[string]Value{"attempt": int64(1)}}
	original := Alternative{"@std/Result[Unit][ReadError]", "error", []Value{cause}}
	result := ErrorResult(original, "@std/Result[Unit][@std/Error]", TypeScope{Module: "first.ms"}).(Alternative)
	view, ok := result.Fields[0].(View)
	if !ok || view.Scope.Module != "first.ms" {
		t.Fatal("Error boundary lost scoped dispatch evidence")
	}
	if _, wrapped := original.Fields[0].(View); wrapped {
		t.Fatal("Error boundary changed the original Result")
	}
	SetField(ContractReceiver(view), "attempt", int64(2))
	if Field(cause, "attempt") != int64(2) {
		t.Fatal("scoped Error boundary copied the concrete error")
	}
}
