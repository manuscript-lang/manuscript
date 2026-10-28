# conform: tags=control-flow,diagnostics,tier-core,with-cleanup
# conform: phase=check
# conform: origin=pkg/tooling/format/format_paragraphs_test.go:101 TestFormatParagraphs
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

    with let resource = acquire():
        run(resource)
    return count
