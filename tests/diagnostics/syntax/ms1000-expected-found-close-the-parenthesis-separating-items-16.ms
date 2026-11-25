// conform: tags=diagnostics
// conform: phase=check
fn use[ListEntry](value ListE|) Void => void
fn broken(
// expect-error: MS1000 3:30-3:31 expected ')', found '|'; close the parenthesis, separating items with commas
// expect-error: MS1000 7:1 unterminated delimiter '(' opened at line 4:10; add the matching ')' before the end of the file
