# conform: tags=formatter,parser,records,strings,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/checker/json_parse_test.go:22 TestParseTypeArgument
type Request:
    model: String

fn f(text: String) Request!:
    let request: Request = try parse(text)
    return ok(request)
