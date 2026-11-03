# conform: tags=diagnostics,generics,strings,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/checker/json_parse_test.go:23 TestParseTypeArgument
fn f[T](text: String) T!:
    return parse[T](text)
