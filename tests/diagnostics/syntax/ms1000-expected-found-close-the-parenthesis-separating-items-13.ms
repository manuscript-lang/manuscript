// conform: tags=diagnostics
// conform: phase=check
fn use[ListEntry](value ListE|) Void => void
// expect-error: MS1000 3:30-3:31 expected ')', found '|'; close the parenthesis, separating items with commas
