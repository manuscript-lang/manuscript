# conform: tags=diagnostics,records,strings,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/checker/json_parse_test.go:19 TestParseTypeArgument
type Request:
    model: String
fn f(text: String) Result[Request, JsonError]:
    return parse[Request](text)
