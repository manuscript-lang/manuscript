# conform: tags=control-flow,formatter,match,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/format/format_paragraphs_test.go:54 TestFormatParagraphs
def process(input: String) -> Int:
    let records = parse(input)
    if records.length() == 0: return 0
    if records.length() > 100: return 1

    let report = summarize(records)
    let payload = encode(report)

    match save(payload):
        case ok(_):
            return 0
        case error(_):
            return 1
