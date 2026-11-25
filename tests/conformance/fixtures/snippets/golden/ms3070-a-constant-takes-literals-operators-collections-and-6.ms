// conform: tags=diagnostics
// conform: phase=check
frozen := b.freeze()
// expect-error: MS3070 3:13 a constant takes literals, operators, collections, and other constants; compute this value in a function
