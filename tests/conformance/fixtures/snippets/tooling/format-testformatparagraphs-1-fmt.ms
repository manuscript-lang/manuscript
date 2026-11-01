# conform: tags=control-flow,formatter,parser,tier-core,scope-cleanup
# conform: phase=parse
# conform: origin=pkg/tooling/format/format_paragraphs_test.go:16 TestFormatParagraphs
fn work(enabled: Bool) Int:
    let count = 2
    if enabled:
        run(count)
    for item in [1, 2]:
        run(item)

    var resource = acquire()
    run(resource)
    resource.close()
    return count
