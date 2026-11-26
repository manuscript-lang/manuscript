// conform: tags=diagnostics
// conform: phase=check
_server := network().serve(
	address: "127.0.0.1:0",
	handler: fn(request) HttpResponse {
		values := [1]
		values.append(2)
		return panic("not executed by lint")
	}
)
// expect-error: MS3070 3:22 a constant takes literals, operators, collections, and other constants; compute this value in a function
// expect-error: MS2001 5:26 unknown type HttpResponse; add: import HttpResponse from "@std/net/http.ms"
// expect-fix: 1:1-1:1 "import HttpResponse from \"@std/net/http.ms\"\n"
