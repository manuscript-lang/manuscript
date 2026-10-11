package checker

// Data services remain explicit standard imports and use ordinary named methods.
func serviceStandards(add func(string, string, string, int) *Type) {
	for _, spec := range []struct {
		module, name string
		arity        int
	}{
		{"queues", "Queue", 1}, {"queues", "QueueError", 0}, {"state", "State", 1},
		{"pools", "Pool", 1}, {"pools", "Lease", 1}, {"pools", "PoolError", 0},
		{"builders", "ListBuilder", 1}, {"builders", "MapBuilder", 2}, {"builders", "SetBuilder", 1},
		{"builders", "BytesBuilder", 0}, {"builders", "StringBuilder", 0},
	} {
		kind := "native"
		if spec.name == "QueueError" || spec.name == "PoolError" {
			kind = "alternative"
		}
		typ := add(spec.module, spec.name, kind, spec.arity)
		for _, variable := range typ.Args {
			variable.Bounds = []*Type{primitive("Shareable")}
		}
	}
	unit, integer, text := primitive("Unit"), primitive("Int"), primitive("String")
	for _, name := range []string{"QueueError", "PoolError"} {
		standardSymbols[name].Type.Def.Cases = []Case{{Name: "Closed"}}
	}
	method := func(name, operation string, params []Param, result *Type) {
		typ := standardSymbols[name].Type
		typ.Def.Operations = append(typ.Def.Operations, Param{operation, function(params, result)})
	}
	fields := func(name string, params ...Param) { standardSymbols[name].Type.Def.Fields = params }
	element := func(name string) *Type { return standardSymbols[name].Type.Args[0] }
	fields("Queue", Param{"capacity", integer})
	method("Queue", "send", []Param{{"value", element("Queue")}}, standard("Result", unit, standard("QueueError")))
	method("Queue", "receive", nil, standard("Optional", element("Queue")))
	method("Queue", "close", nil, unit)
	fields("State", Param{"value", element("State")})
	method("State", "get", nil, element("State"))
	method("State", "set", []Param{{"value", element("State")}}, unit)
	method("State", "swap", []Param{{"value", element("State")}}, element("State"))
	fields("Pool", Param{"resources", standard("List", element("Pool"))})
	method("Pool", "acquire", nil, standard("Result", standard("Lease", element("Pool")), standard("PoolError")))
	method("Pool", "close", nil, unit)
	method("Lease", "get", nil, standard("Result", element("Lease"), standard("PoolError")))
	method("Lease", "close", nil, unit)
	method("ListBuilder", "append", []Param{{"value", element("ListBuilder")}}, unit)
	method("ListBuilder", "freeze", nil, standard("List", element("ListBuilder")))
	key, value := standardSymbols["MapBuilder"].Type.Args[0], standardSymbols["MapBuilder"].Type.Args[1]
	key.Bounds = []*Type{primitive("Hashable")}
	method("MapBuilder", "with_entry", []Param{{"key", key}, {"value", value}}, unit)
	method("MapBuilder", "freeze", nil, standard("Map", key, value))
	standardSymbols["SetBuilder"].Type.Args[0].Bounds = []*Type{primitive("Hashable")}
	method("SetBuilder", "with_value", []Param{{"value", element("SetBuilder")}}, unit)
	method("SetBuilder", "freeze", nil, standard("Set", element("SetBuilder")))
	method("BytesBuilder", "append", []Param{{"value", integer}}, unit)
	method("BytesBuilder", "concat", []Param{{"values", standard("Bytes")}}, unit)
	method("BytesBuilder", "freeze", nil, standard("Bytes"))
	method("StringBuilder", "append", []Param{{"value", text}}, unit)
	method("StringBuilder", "freeze", nil, text)
}
