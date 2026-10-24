# conform: tags=formatter,parser,records,strings,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/checker/json_parse_test.go:19 TestParseTypeArgument
type Request:
    model: String

def f(text: String) -> Result[Request, JsonError]:
    return parse[Request](text)
