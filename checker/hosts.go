package checker

func hostStandards(add func(string, string, string, int) *Type) {
	for _, spec := range []struct{ module, name, kind string }{
		{"http", "Network", "contract"}, {"http", "HttpServer", "contract"}, {"http", "HttpRequest", "record"}, {"http", "HttpResponse", "record"},
		{"process", "Commands", "contract"}, {"process", "CommandOutput", "record"}, {"process", "CommandError", "alternative"},
	} {
		add(spec.module, spec.name, spec.kind, 0)
	}
	integer, text, unit := primitive("Int"), primitive("String"), primitive("Unit")
	shared := func(name string) *Type { t := standard(name); t.Shared = true; return t }
	field := func(name string, fields ...Param) { standardSymbols[name].Type.Def.Fields = fields }
	operation := func(name, method string, params []Param, result *Type) {
		typ := standardSymbols[name].Type
		typ.Def.Operations = append(typ.Def.Operations, Param{method, function(params, result)})
	}
	field("HttpRequest", Param{"method", text}, Param{"path", text}, Param{"query", text}, Param{"headers", standard("Map", text, standard("Bytes"))}, Param{"body", standard("Bytes")})
	field("HttpResponse", Param{"status", integer}, Param{"headers", standard("Map", text, text)}, Param{"body", standard("Bytes")})
	field("CommandOutput", Param{"exit_code", integer}, Param{"stdout", standard("Bytes")}, Param{"stderr", standard("Bytes")})
	standardSymbols["CommandError"].Type.Def.Cases = []Case{{Name: "InvalidInput"}, {Name: "Unavailable"}, {Name: "TimedOut"}, {Name: "OutputLimit"}, {Name: "Failed", Fields: []Param{{"message", text}}}}
	operation("Commands", "run", []Param{{"program", text}, {"arguments", standard("List", text)}, {"input", standard("Bytes")}, {"max_output_bytes", integer}, {"timeout", standard("Duration")}}, standard("Result", standard("CommandOutput"), standard("CommandError")))
	operation("Network", "serve", []Param{{"address", text}, {"handler", function([]Param{{"request", standard("HttpRequest")}}, standard("HttpResponse"))}, {"limit", integer}, {"max_body_bytes", integer}, {"max_response_bytes", integer}, {"timeout", standard("Duration")}, {"grace", standard("Duration")}}, standard("Result", shared("HttpServer"), standard("IoError")))
	operation("Network", "close", nil, unit)
	operation("HttpServer", "address", nil, text)
	operation("HttpServer", "wait", nil, standard("Result", unit, standard("IoError")))
	operation("HttpServer", "close", nil, unit)
}
