# conform: tags=closures,formatter,parser,records,strings,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/checker/json_parse_test.go:24 TestParseTypeArgument
type Request:
    callback: fn() Int

fn f(text: String) Request!JsonError:
    return parse[Request](text)
