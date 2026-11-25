// conform: tags=diagnostics
// conform: phase=check
let é = 1
// expect-error: MS1000 3:5 unexpected source character 'é'; non-ASCII characters are only allowed inside text and comments, and identifiers are ASCII
