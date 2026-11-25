// conform: tags=diagnostics
// conform: phase=check
x := 1 + 日
// expect-error: MS1000 3:10 unexpected source character '日'; non-ASCII characters are only allowed inside text and comments, and identifiers are ASCII
