package msruntime

import (
	"reflect"
	"testing"
)

func TestBoundNativeCallMatchesBoundMember(t *testing.T) {
	ctx := RootExecution()
	scope := TypeScope{Module: "m", Args: []TypeScope{{Module: "m"}}}
	for _, tc := range []struct {
		kind, name, native, result string
		receiver                   func() Value
		labels                     []string
		args                       []Value
	}{
		{"String", "trim", "string/trim", "String", func() Value { return "  a " }, nil, nil},
		{"String", "split", "string/split", "@std/List[String]", func() Value { return "a,b" }, []string{"separator"}, []Value{","}},
		{"List", "set", "collections/set", "@std/List[Int]", func() Value { return NewList("@std/List[Int]", []Value{int64(1), int64(2)}) }, []string{"index", "value"}, []Value{int64(-1), int64(9)}},
		{"List", "contains", "collections/contains", "Bool", func() Value { return NewList("@std/List[Int]", []Value{int64(1)}) }, []string{"value"}, []Value{int64(1)}},
		// A member without a library body keeps ordinary dispatch.
		{"List", "length", "length", "Int", func() Value { return NewList("@std/List[Int]", []Value{int64(1)}) }, nil, nil},
	} {
		var arguments []Argument
		for i, label := range tc.labels {
			arguments = append(arguments, Argument{label, tc.args[i]})
		}
		want := Invoke(ctx, NativeMemberResult(tc.receiver(), tc.name, tc.result, scope), arguments)
		got := CallNative(ctx, BindNativeCall(tc.kind, tc.name, tc.native, tc.result, scope), append([]Value{tc.receiver()}, tc.args...))
		if !reflect.DeepEqual(got, want) {
			t.Errorf("%s.%s: CallNative = %#v, bound member = %#v", tc.kind, tc.name, got, want)
		}
	}
}

func TestBoundNativeCallSelectsOutputScopeForKeyTransforms(t *testing.T) {
	input := TypeScope{Module: "input", Args: []TypeScope{{Module: "in"}}}
	output := TypeScope{Module: "output", Args: []TypeScope{{Module: "out"}}}
	for _, tc := range []struct{ kind, name string }{{"Set", "map"}, {"Map", "map_keys"}} {
		call := BindNativeCall(tc.kind, tc.name, "collections/"+tc.name, "r", input, output).(*NativeCall)
		if call.scope.Module != "out" {
			t.Errorf("%s.%s scope = %q, want the output scope", tc.kind, tc.name, call.scope.Module)
		}
	}
	if call := BindNativeCall("List", "contains", "collections/contains", "Bool", input).(*NativeCall); call.scope.Module != "in" {
		t.Errorf("List scope = %q, want the element scope", call.scope.Module)
	}
	if call := BindNativeCall("String", "trim", "string/trim", "String", input).(*NativeCall); call.scoped {
		t.Error("String members must not copy the execution")
	}
}
