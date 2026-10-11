package checker

import "strings"

var standardSymbols map[string]*Symbol
var standardModules map[string]map[string]*Symbol

func init() {
	standardSymbols = map[string]*Symbol{}
	standardModules = map[string]map[string]*Symbol{}
	add := func(module, name, kind string, arity int) *Type {
		symbol := &Symbol{Name: name, ID: "@std/" + name, Kind: "type", Module: "@std/" + module + ".ms", Export: true, Native: name}
		def := &Definition{Symbol: symbol, Kind: kind}
		t := &Type{Name: name, ID: symbol.ID, Kind: kind, Def: def}
		symbol.Type = t
		for i := 0; i < arity; i++ {
			v := &Type{Name: string(rune('T' + i)), ID: symbol.ID + "/" + string(rune('T'+i)), Kind: "variable"}
			def.Variables = append(def.Variables, v)
			t.Args = append(t.Args, v)
		}
		symbol.Variables = def.Variables
		standardSymbols[name] = symbol
		if standardModules[symbol.Module] == nil {
			standardModules[symbol.Module] = map[string]*Symbol{}
		}
		standardModules[symbol.Module][name] = symbol
		return t
	}
	for _, spec := range []struct {
		module, name, kind string
		arity              int
	}{{"decimal", "Decimal", "native", 0}, {"bytes", "Bytes", "native", 0}, {"collections", "List", "native", 1}, {"collections", "Map", "native", 2}, {"collections", "Set", "native", 1}, {"collections", "MapEntry", "record", 2}, {"optional", "Optional", "alternative", 1}, {"result", "Result", "alternative", 2}, {"cleanup", "Closeable", "contract", 0}, {"time", "Duration", "native", 0}, {"time", "Instant", "native", 0}, {"time", "Clock", "contract", 0}, {"io", "IoError", "alternative", 0}, {"io", "Files", "contract", 0}, {"io", "File", "contract", 0}, {"io", "ReadStream", "contract", 0}, {"io", "WriteStream", "contract", 0}, {"cli", "Process", "record", 0}, {"tasks", "ExecutionError", "alternative", 0}, {"tasks", "OperationId", "native", 0}, {"tasks", "StartError", "alternative", 0}, {"tasks", "WorkStatus", "alternative", 0}, {"tasks", "BackgroundFailure", "alternative", 0}, {"tasks", "Background", "native", 0}} {
		add(spec.module, spec.name, spec.kind, spec.arity)
	}
	serviceStandards(add)
	hostStandards(add)
	optional := standardSymbols["Optional"].Type
	optional.Def.Cases = []Case{{"some", []Param{{"value", optional.Args[0]}}}, {Name: "none"}}
	result := standardSymbols["Result"].Type
	result.Def.Cases = []Case{{"ok", []Param{{"value", result.Args[0]}}}, {"error", []Param{{"cause", result.Args[1]}}}}
	entry := standardSymbols["MapEntry"].Type
	entry.Def.Fields = []Param{{"key", entry.Args[0]}, {"value", entry.Args[1]}}
	for _, name := range []string{"List", "Set"} {
		standardSymbols[name].Variables[0].Bounds = []*Type{primitive("Shareable")}
	}
	standardSymbols["Set"].Variables[0].Bounds = append(standardSymbols["Set"].Variables[0].Bounds, primitive("Hashable"))
	standardSymbols["Map"].Variables[0].Bounds = []*Type{primitive("Hashable")}
	standardSymbols["Map"].Variables[1].Bounds = []*Type{primitive("Shareable")}
	standardSymbols["MapEntry"].Variables[0].Bounds = []*Type{primitive("Hashable")}
	standardSymbols["MapEntry"].Variables[1].Bounds = []*Type{primitive("Shareable")}
	op := func(name, method string, params []Param, result *Type) {
		t := standardSymbols[name].Type
		t.Def.Operations = append(t.Def.Operations, Param{method, function(params, result)})
	}
	unit := primitive("Unit")
	integer := primitive("Int")
	text := primitive("String")
	for _, name := range []string{"Closeable", "File", "ReadStream", "WriteStream"} {
		op(name, "close", nil, unit)
	}
	shared := func(name string) *Type { t := standard(name); t.Shared = true; return t }
	op("Clock", "now", nil, standard("Instant"))
	op("Files", "open", []Param{{"path", text}}, standard("Result", shared("File"), standard("IoError")))
	for _, name := range []string{"File", "ReadStream"} {
		op(name, "read", []Param{{"max_bytes", integer}}, standard("Result", standard("Optional", standard("Bytes")), standard("IoError")))
	}
	op("WriteStream", "write", []Param{{"data", standard("Bytes")}}, standard("Result", unit, standard("IoError")))
	op("WriteStream", "flush", nil, standard("Result", unit, standard("IoError")))
	standardSymbols["Process"].Type.Def.Fields = []Param{{"arguments", standard("List", text)}, {"environment", standard("Map", text, text)}, {"stdin", shared("ReadStream")}, {"stdout", shared("WriteStream")}, {"stderr", shared("WriteStream")}, {"files", shared("Files")}, {"clock", shared("Clock")}}
	standardSymbols["Process"].Type.Def.Fields = append(standardSymbols["Process"].Type.Def.Fields, Param{"network", shared("Network")}, Param{"commands", shared("Commands")})
	standardSymbols["IoError"].Type.Def.Cases = []Case{{Name: "Closed"}, {Name: "InvalidInput"}, {Name: "Unavailable"}, {Name: "Failed", Fields: []Param{{"message", text}}}}
	standardSymbols["StartError"].Type.Def.Cases = []Case{{Name: "Closed"}, {Name: "Full"}}
	for _, name := range strings.Fields("Running Succeeded Failed Cancelled Crashed Unknown") {
		standardSymbols["WorkStatus"].Type.Def.Cases = append(standardSymbols["WorkStatus"].Type.Def.Cases, Case{Name: name})
	}
	standardSymbols["BackgroundFailure"].Type.Def.Cases = []Case{{Name: "Failed", Fields: []Param{{"operation", standard("OperationId")}, {"cause", text}}}, {Name: "Crashed", Fields: []Param{{"operation", standard("OperationId")}, {"message", text}}}}
	standardSymbols["ExecutionError"].Type.Def.Cases = []Case{{Name: "TimedOut"}, {Name: "Crashed", Fields: []Param{{"operation", standard("OperationId")}, {"message", text}}}}
	addFn := func(module, name string, vars []*Type, params []Param, result *Type) {
		s := &Symbol{Name: name, ID: "@std/" + name, Kind: "fn", Module: "@std/" + module + ".ms", Export: true, Native: name, Variables: vars, Type: function(params, result)}
		if standardModules[s.Module] == nil {
			standardModules[s.Module] = map[string]*Symbol{}
		}
		standardModules[s.Module][name] = s
		standardSymbols[name] = s
	}
	addFn("faults", "panic", nil, []Param{{"message", text}}, primitive("Never"))
	addFn("tasks", "check_cancelled", nil, nil, unit)
	addFn("time", "sleep", nil, []Param{{"duration", standard("Duration")}}, unit)
	t := &Type{Name: "T", ID: "@std/map_error/T", Kind: "variable"}
	e := &Type{Name: "E", ID: "@std/map_error/E", Kind: "variable"}
	f := &Type{Name: "F", ID: "@std/map_error/F", Kind: "variable"}
	addFn("result", "map_error", []*Type{t, e, f}, []Param{{"result", standard("Result", t, e)}, {"transform", function([]Param{{"cause", e}}, f)}}, standard("Result", t, f))
	addFn("tasks", "parallel", nil, nil, nil)
	t = &Type{Name: "T", ID: "@std/parallel_map/T", Kind: "variable", Bounds: []*Type{primitive("Shareable")}}
	e = &Type{Name: "U", ID: "@std/parallel_map/U", Kind: "variable", Bounds: []*Type{primitive("Shareable")}}
	addFn("tasks", "parallel_map", []*Type{t, e}, []Param{{"items", standard("List", t)}, {"operation", function([]Param{{"item", t}}, e)}, {"limit", integer}}, standard("Result", standard("List", e), standard("ExecutionError")))
	libraryStandards(add)
}
