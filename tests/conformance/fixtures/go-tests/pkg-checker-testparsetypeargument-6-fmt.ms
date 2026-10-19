# conform: tags=formatter,generics,parser,strings,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/checker/json_parse_test.go:23 TestParseTypeArgument
fn f[T](text: String) Result[T, JsonError]:
    return parse[T](text)
