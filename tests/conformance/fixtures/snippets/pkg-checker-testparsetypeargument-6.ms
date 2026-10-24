# conform: tags=diagnostics,generics,strings,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/checker/json_parse_test.go:23 TestParseTypeArgument
def f[T](text: String) -> Result[T, JsonError]:
    return parse[T](text)
