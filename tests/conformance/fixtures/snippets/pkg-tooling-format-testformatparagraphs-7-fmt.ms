# conform: tags=control-flow,formatter,parser,tier-core,with-cleanup
# conform: phase=parse
# conform: origin=pkg/tooling/format/format_paragraphs_test.go:83 TestFormatParagraphs
fn work(enabled: Bool) Int:
    let count = 2

    if enabled:
        run(count)
    else if count > 0: run(1)
    else:
        run(0)

    while enabled:
        if count == 0: break

        run(count)
        break

    for item in [1, 2]:
        if item == 1: continue

        run(item)

    with resource = acquire():
        run(resource)
    return count
