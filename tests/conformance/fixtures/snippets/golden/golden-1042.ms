// conform: tags=diagnostics
// conform: phase=check
fn work() Unit:
    expect_false(parse("\"line\r\n\r\nbreak\"\r\n\"\"\r\n", options)? != [["line\n\nbreak"], [""]])?
