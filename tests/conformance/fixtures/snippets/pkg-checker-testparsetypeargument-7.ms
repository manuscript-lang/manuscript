# conform: tags=closures,diagnostics,records,strings,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/checker/json_parse_test.go:24 TestParseTypeArgument
type Request:
    callback: Callable[[], Int]

def f(text: String) -> Result[Request, JsonError]:
    return parse[Request](text)
