// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=documentation/core-language/types/alternatives.md:26
payment := Payment.Paid("receipt-42")
declined Payment := Declined("Card rejected")
// expect-error: MS3070 4:20 a constant takes literals, operators, collections, and other constants; compute this value in a function
// expect-error: MS3070 5:21 a constant takes literals, operators, collections, and other constants; compute this value in a function
