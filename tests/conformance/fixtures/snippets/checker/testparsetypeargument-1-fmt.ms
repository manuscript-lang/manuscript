# conform: tags=formatter,parser,strings,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/checker/json_parse_test.go:18 TestParseTypeArgument
fn f(text: String) JsonValue!:
    return parse(text)
