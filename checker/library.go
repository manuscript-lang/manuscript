package checker

import (
	rt "github.com/manuscript-lang/manuscript/runtime"
	"strings"
)

func libraryStandards(add func(string, string, string, int) *Type) {
	for _, name := range []string{"Connection", "Listener", "DatagramSocket"} {
		add("net", name, "contract", 0)
	}
	d := add("net", "Datagram", "record", 0)
	d.Def.Fields = []Param{{"data", standard("Bytes")}, {"sender", primitive("String")}}

	for _, item := range []struct{ module, name, kind string }{{"tls", "TlsOptions", "record"}, {"tls", "CertificateInfo", "record"}, {"tls", "TlsInfo", "record"}, {"net", "DnsRecord", "record"}, {"http", "HttpClient", "contract"}, {"http", "ResponseBody", "contract"}, {"http", "HttpExchange", "contract"}, {"websocket", "WebSocket", "contract"}} {
		add(item.module, item.name, item.kind, 0)
	}

	for _, name := range []string{"HttpClientOptions", "HttpServerOptions"} {
		add("http", name, "record", 0)
	}
	add("websocket", "WebSocketOptions", "record", 0)
	add("websocket", "WebSocketMessage", "record", 0)
	errType := add("errors", "LibraryError", "alternative", 0)
	for _, code := range strings.Fields("InvalidInput InvalidData OutOfRange LimitExceeded NotFound AlreadyExists PermissionDenied Unsupported Closed Timeout AuthenticationFailed") {
		errType.Def.Cases = append(errType.Def.Cases, Case{Name: code})
	}
	errType.Def.Cases = append(errType.Def.Cases, Case{Name: "Failed", Fields: []Param{{"message", primitive("String")}}})
	add("bigint", "BigInt", "native", 0)
	add("regex", "Regex", "native", 0)
	add("time", "Timestamp", "native", 0)
	for _, item := range []struct{ module, name string }{{"json", "JsonValue"}, {"json", "JsonLimits"}, {"url", "QueryEntry"}, {"url", "Url"}, {"csv", "CsvOptions"}, {"fs", "FileInfo"}, {"fs", "DirectoryEntry"}, {"http", "ClientResponse"}, {"system", "SystemInfo"}, {"archive", "ArchiveEntry"}, {"archive", "ArchiveLimits"}} {
		add(item.module, item.name, "record", 0)
	}
	standardSymbols["JsonValue"].Type.Kind = "alternative"
	standardSymbols["JsonValue"].Type.Def.Kind = "alternative"
	for _, item := range []struct{ module, name string }{{"fs", "FileSystem"}, {"random", "Entropy"}, {"time", "WallClock"}, {"system", "System"}} {
		add(item.module, item.name, "contract", 0)
	}
	parse := func(s string) *Type { return libraryParseType(s, nil) }
	field := func(name string, ps ...rt.LibraryParam) {
		for _, p := range ps {
			standardSymbols[name].Type.Def.Fields = append(standardSymbols[name].Type.Def.Fields, Param{p.Name, parse(p.Type)})
		}
	}
	field("JsonLimits", rt.LibraryParam{Name: "max_bytes", Type: "Int"}, rt.LibraryParam{Name: "max_depth", Type: "Int"}, rt.LibraryParam{Name: "max_values", Type: "Int"})

	field("TlsOptions", rt.LibraryParam{Name: "server_name", Type: "String"}, rt.LibraryParam{Name: "roots_pem", Type: "String"}, rt.LibraryParam{Name: "certificate_pem", Type: "String"}, rt.LibraryParam{Name: "private_key_pem", Type: "String"}, rt.LibraryParam{Name: "alpn", Type: "List[String]"}, rt.LibraryParam{Name: "require_client_certificate", Type: "Bool"})
	field("CertificateInfo", rt.LibraryParam{Name: "subject", Type: "String"}, rt.LibraryParam{Name: "issuer", Type: "String"}, rt.LibraryParam{Name: "dns_names", Type: "List[String]"}, rt.LibraryParam{Name: "not_before", Type: "Timestamp"}, rt.LibraryParam{Name: "not_after", Type: "Timestamp"}, rt.LibraryParam{Name: "der", Type: "Bytes"})
	for _, p := range []rt.LibraryParam{{Name: "kind", Type: "String"}, {Name: "value", Type: "String"}, {Name: "priority", Type: "Int"}, {Name: "weight", Type: "Int"}, {Name: "port", Type: "Int"}} {
		field("DnsRecord", p)
	}

	for _, p := range []rt.LibraryParam{{Name: "max_redirects", Type: "Int"}, {Name: "max_idle_connections", Type: "Int"}, {Name: "max_header_bytes", Type: "Int"}, {Name: "idle_timeout", Type: "Duration"}, {Name: "decompress", Type: "Bool"}, {Name: "cookies", Type: "Bool"}, {Name: "tls", Type: "TlsOptions"}} {
		field("HttpClientOptions", p)
	}
	for _, p := range []rt.LibraryParam{{Name: "max_requests", Type: "Int"}, {Name: "max_body_bytes", Type: "Int"}, {Name: "max_response_bytes", Type: "Int"}, {Name: "max_header_bytes", Type: "Int"}, {Name: "timeout", Type: "Duration"}, {Name: "grace", Type: "Duration"}, {Name: "tls", Type: "Optional[TlsOptions]"}} {
		field("HttpServerOptions", p)
	}
	for _, p := range []rt.LibraryParam{{Name: "max_message_bytes", Type: "Int"}, {Name: "timeout", Type: "Duration"}, {Name: "tls", Type: "TlsOptions"}, {Name: "compression", Type: "Bool"}} {
		field("WebSocketOptions", p)
	}
	field("WebSocketMessage", rt.LibraryParam{Name: "data", Type: "Bytes"}, rt.LibraryParam{Name: "text", Type: "Bool"})

	for _, p := range []rt.LibraryParam{{Name: "version", Type: "Int"}, {Name: "cipher_suite", Type: "Int"}, {Name: "alpn", Type: "String"}, {Name: "peer_certificates", Type: "List[Bytes]"}, {Name: "verified", Type: "Bool"}} {
		field("TlsInfo", p)
	}
	j := standardSymbols["JsonValue"].Type
	for _, cs := range []struct{ name, label, typ string }{{"Null", "", ""}, {"BoolValue", "value", "Bool"}, {"NumberValue", "text", "String"}, {"StringValue", "value", "String"}, {"ArrayValue", "values", "List[JsonValue]"}, {"ObjectValue", "values", "Map[String][JsonValue]"}} {
		c := Case{Name: cs.name}
		if cs.typ != "" {
			c.Fields = []Param{{cs.label, parse(cs.typ)}}
		}
		j.Def.Cases = append(j.Def.Cases, c)
	}
	field("QueryEntry", rt.LibraryParam{Name: "key", Type: "String"}, rt.LibraryParam{Name: "value", Type: "String"})
	field("Url", rt.LibraryParam{Name: "scheme", Type: "String"}, rt.LibraryParam{Name: "host", Type: "String"}, rt.LibraryParam{Name: "port", Type: "Optional[Int]"}, rt.LibraryParam{Name: "path", Type: "String"}, rt.LibraryParam{Name: "query", Type: "String"}, rt.LibraryParam{Name: "fragment", Type: "String"})
	field("CsvOptions", rt.LibraryParam{Name: "delimiter", Type: "String"}, rt.LibraryParam{Name: "line_ending", Type: "String"})
	field("FileInfo", rt.LibraryParam{Name: "name", Type: "String"}, rt.LibraryParam{Name: "size", Type: "Int"}, rt.LibraryParam{Name: "directory", Type: "Bool"}, rt.LibraryParam{Name: "symlink", Type: "Bool"}, rt.LibraryParam{Name: "modified", Type: "Timestamp"})
	field("DirectoryEntry", rt.LibraryParam{Name: "name", Type: "String"}, rt.LibraryParam{Name: "directory", Type: "Bool"}, rt.LibraryParam{Name: "symlink", Type: "Bool"})
	field("ClientResponse", rt.LibraryParam{Name: "status", Type: "Int"}, rt.LibraryParam{Name: "headers", Type: "Map[String][List[String]]"}, rt.LibraryParam{Name: "body", Type: "Bytes"})
	field("SystemInfo", rt.LibraryParam{Name: "os", Type: "String"}, rt.LibraryParam{Name: "architecture", Type: "String"}, rt.LibraryParam{Name: "cpu_count", Type: "Int"})
	field("ArchiveEntry", rt.LibraryParam{Name: "path", Type: "String"}, rt.LibraryParam{Name: "data", Type: "Bytes"}, rt.LibraryParam{Name: "directory", Type: "Bool"})
	field("ArchiveLimits", rt.LibraryParam{Name: "max_entries", Type: "Int"}, rt.LibraryParam{Name: "max_entry_bytes", Type: "Int"}, rt.LibraryParam{Name: "max_total_bytes", Type: "Int"})
	for _, spec := range rt.Library {
		vars := map[string]*Type{}
		var variables []*Type
		native := spec.Module + "/" + spec.Name
		for _, v := range spec.Variables {
			t := &Type{Name: v.Name, ID: "@std/" + native + "/" + v.Name, Kind: "variable"}
			if v.Type != "" {
				t.Bounds = []*Type{primitive(v.Type)}
			}
			vars[v.Name] = t
			variables = append(variables, t)
		}
		params := []Param{}
		for _, p := range spec.Params {
			params = append(params, Param{p.Name, libraryParseType(p.Type, vars)})
		}
		s := &Symbol{Name: spec.Name, ID: "@std/" + native, Kind: "fn", Module: "@std/" + spec.Module + ".ms", Export: true, Native: native, Variables: variables, Type: function(params, libraryParseType(spec.Result, vars))}
		if standardModules[s.Module] == nil {
			standardModules[s.Module] = map[string]*Symbol{}
		}
		standardModules[s.Module][s.Name] = s
	}
	libraryCapabilities()
}
func libraryParseType(s string, vars map[string]*Type) *Type {
	if strings.HasPrefix(s, "fn(") {
		end := strings.Index(s, ")->")
		var ps []Param
		for _, item := range strings.Split(s[3:end], ";") {
			if item == "" {
				continue
			}
			name, typ, _ := strings.Cut(item, ":")
			ps = append(ps, Param{name, libraryParseType(typ, vars)})
		}
		return function(ps, libraryParseType(s[end+3:], vars))
	}
	shared := strings.HasSuffix(s, "&Shareable")
	s = strings.TrimSuffix(s, "&Shareable")
	name := s
	var args []*Type
	if at := strings.IndexByte(s, '['); at >= 0 {
		name = s[:at]
		for at < len(s) {
			start := at + 1
			depth := 1
			at++
			for at < len(s) && depth > 0 {
				if s[at] == '[' {
					depth++
				}
				if s[at] == ']' {
					depth--
				}
				at++
			}
			args = append(args, libraryParseType(s[start:at-1], vars))
		}
	}
	var t *Type
	if vars[name] != nil {
		t = vars[name]
	} else if standardSymbols[name] != nil {
		t = standard(name, args...)
	} else {
		t = primitive(name)
	}
	if shared {
		copy := *t
		copy.Shared = true
		t = &copy
	}
	return t
}
func libraryCapabilities() {
	method := func(typ, name, result string, ps ...rt.LibraryParam) {
		params := []Param{}
		for _, p := range ps {
			params = append(params, Param{p.Name, libraryParseType(p.Type, nil)})
		}
		t := standardSymbols[typ].Type
		t.Def.Operations = append(t.Def.Operations, Param{name, function(params, libraryParseType(result, nil))})
	}
	for _, s := range rt.LibraryMethods {
		method(s.Receiver, s.Name, s.Result, s.Params...)
	}
	for _, p := range []rt.LibraryParam{{Name: "filesystem", Type: "FileSystem&Shareable"}, {Name: "entropy", Type: "Entropy&Shareable"}, {Name: "wall_clock", Type: "WallClock&Shareable"}, {Name: "system", Type: "System&Shareable"}} {
		standardSymbols["Process"].Type.Def.Fields = append(standardSymbols["Process"].Type.Def.Fields, Param{p.Name, libraryParseType(p.Type, nil)})
	}
}
