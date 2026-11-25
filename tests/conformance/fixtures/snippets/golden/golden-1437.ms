// conform: tags=diagnostics
// conform: phase=check
".to_bytes()
    while true {
        _written := stream.write_bytes(data: chunk)
    }
// expect-error: MS1001 3:1 unterminated text literal; text must close with '"' on the same line, so add the quote or write \\n for a line break
