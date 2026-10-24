# conform: tags=diagnostics,strings,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/checker/json_parse_test.go:18 TestParseTypeArgument
def f(text: String) -> Result[JsonValue, JsonError]:
    return parse(text)
