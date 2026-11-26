// conform: tags=control-flow,diagnostics,faults,formatter,generics,lists,maps,match,modules,stdlib-http,strings,tier-io,try-result
// conform: phase=check,parse
// conform: origin=tests/e2e/testdata/stdlib/support/http.ms
import (
	panic from "@std/core.ms",
	HttpHeaders, headers from "@std/net/http.ms",
)

// Explicit fixture migration from the old text maps; no runtime coercion.
export fn text_headers(fields Map[String, String]) HttpHeaders! {
	var result = headers()
	for name in fields.keys() {
		_appended := (
			result.append(
				name,
				fields.get(name) or panic(
					"called Optional.get() on null"
				),
			)
		)?
	}
	return ok(result)
}

export fn list_headers(fields Map[String, List[String]]) HttpHeaders! {
	var result = headers()
	for name in fields.keys() {
		for item in (fields.get(name) or panic("called Optional.get() on null")) {
			_appended := (result.append(name, item))?
		}
	}
	return ok(result)
}

// Streaming callbacks return plain Error values, so a result from any operation passes
// through unchanged.
export fn http_result[T](move outcome T!) T! {
	return outcome
}
// expect-exit: 0
