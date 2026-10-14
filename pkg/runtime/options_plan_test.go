package msruntime

import (
	"reflect"
	"testing"
)

// Every declaration's planned normalization must agree with the general
// adapter for omitted, absent, present, negative and plain arguments.
func TestPlannedOptionsMatchGeneralAdapter(t *testing.T) {
	optional := func(tag string, fields ...Value) Value {
		return Alternative{Type: "@std/Optional[Int]", Tag: tag, Fields: fields}
	}
	samples := []Value{nil, optional("none"), optional("some", int64(5)), optional("some", int64(-1)), optional("some", Duration(7)), optional("some", Duration(-7)), int64(3), Duration(9), "text", Unit{}}
	for _, spec := range Library {
		plan := planOptions(spec.Name, spec.Params)
		for _, sample := range samples {
			for _, length := range []int{0, len(spec.Params) / 2, len(spec.Params)} {
				args := make([]Value, length)
				for i := range args {
					args[i] = sample
				}
				before := append([]Value{}, args...)
				want, wantOK := nativeOptions(spec.Name, spec.Params, args)
				got, gotOK := plan.normalize(args)
				if gotOK != wantOK || !reflect.DeepEqual(got, want) {
					t.Fatalf("%s/%s with %#v: planned %#v %v, general %#v %v", spec.Module, spec.Name, sample, got, gotOK, want, wantOK)
				}
				if !reflect.DeepEqual(args, before) {
					t.Fatalf("%s/%s mutated its arguments", spec.Module, spec.Name)
				}
			}
		}
	}
}
