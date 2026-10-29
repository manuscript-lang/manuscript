# conform: tags=formatter,parser,records,strings,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/checker/json_parse_test.go:21 TestParseTypeArgument
type Request:
    model: String

fn f(text: String) Result[Request, JsonError]:
    let request = try parse[Request](text)
    return ok(request)
