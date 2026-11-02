# conform: tags=control-flow,diagnostics,match,strings,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/format/format_paragraphs_test.go:54 TestFormatParagraphs
fn process(input: String) Int:
    let records = parse(input)
    if records.length() == 0: return 0
    if records.length() > 100: return 1

    let report = summarize(records)
    let payload = encode(report)

    match save(payload):
        ok(_):
            return 0
        error(_):
            return 1
