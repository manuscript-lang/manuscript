# conform: tags=diagnostics,records,strings,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/checker/json_parse_test.go:22 TestParseTypeArgument
type Request:
    model: String

def f(text: String) -> Result[Request, JsonError]:
    let request: Request = try parse(text)
    return ok(request)
