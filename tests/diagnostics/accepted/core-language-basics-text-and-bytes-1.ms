// conform: tags=diagnostics,formatter,interpolation,tier-core
// conform: phase=check,parse
// conform: origin=documentation/core-language/basics/text-and-bytes.md:26
quote := "She said \"hello\"."
template := "Literal braces: {name}"
lines := "first\nsecond"
symbol := "\u{1F642}"
// expect-exit: 0
