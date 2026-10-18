package checker

import "testing"

func TestFieldAndCaseSpecializationRetainsCopies(t *testing.T) {
	variable := &Type{ID: "T", Name: "T", Kind: "variable"}
	unbound := &Type{ID: "U", Name: "U", Kind: "variable"}
	argument := primitive("Int")
	callback := function([]Param{{Name: "value", Type: variable}}, unbound)
	callback.Defaults = map[string]bool{"value": true}
	fields := []Param{{Name: "direct", Type: variable}, {Name: "callback", Type: callback}}
	typ := &Type{Args: []*Type{argument}, Def: &Definition{
		Variables: []*Type{variable, unbound},
		Fields:    fields,
		Cases:     []Case{{Name: "Empty"}, {Name: "Value", Fields: fields}},
	}}
	for range 2 {
		specialized := Fields(typ)
		cases := Cases(typ)
		if len(cases) != 2 || cases[0].Name != "Empty" || cases[0].Fields != nil || cases[1].Name != "Value" {
			t.Fatalf("changed case names or empty payload: %#v", cases)
		}
		for _, got := range [][]Param{specialized, cases[1].Fields} {
			if len(got) != 2 || got[0].Name != "direct" || got[1].Name != "callback" || got[0].Type != argument {
				t.Fatalf("lost supplied argument sharing or field identity: %#v", got)
			}
			fn := got[1].Type
			if fn == callback || len(fn.Params) != 1 || fn.Params[0].Name != "value" || fn.Params[0].Type != argument || fn.Result == unbound || !Same(fn.Result, unbound) || !fn.Defaults["value"] {
				t.Fatalf("changed nested function substitution: %#v", fn)
			}
			got[0].Name = "changed"
			fn.Params[0].Name = "changed"
			fn.Result.Name = "changed"
		}
		if fields[0].Name != "direct" || callback.Params[0].Name != "value" || unbound.Name != "U" {
			t.Fatal("specialization mutated its declaration")
		}
		// A later query sees the new arguments, with no cross-query cache.
		argument = primitive("String")
		typ.Args[0] = argument
	}
}

func TestFieldAndCaseSpecializationNilCollections(t *testing.T) {
	for _, typ := range []*Type{{}, {Def: &Definition{}}, {Def: &Definition{Fields: []Param{}, Cases: []Case{}}}} {
		if Fields(typ) != nil || Cases(typ) != nil {
			t.Fatal("empty declarations must retain nil fields and cases")
		}
	}
}
