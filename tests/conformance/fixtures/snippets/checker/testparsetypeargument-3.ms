# conform: tags=diagnostics,records,strings,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/checker/json_parse_test.go:20 TestParseTypeArgument
type Request:
    model: String

fn f(text: String) Request!:
    return parse(text)
