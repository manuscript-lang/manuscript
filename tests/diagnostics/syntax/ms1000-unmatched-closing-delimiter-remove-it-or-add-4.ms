// conform: tags=diagnostics
// conform: phase=check
]
fn broken(
// expect-error: MS1000 3:1-3:2 unmatched closing delimiter ']'; remove it or add the matching opener before it
// expect-error: MS1000 7:1 unterminated delimiter '(' opened at line 4:10; add the matching ')' before the end of the file
