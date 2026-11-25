// conform: tags=diagnostics
// conform: phase=check
type ${1:Name} {
    ${0:field: String}
}
// expect-error: MS1000 3:6-3:7 unexpected source character '$'; this character is not part of Manuscript's syntax outside text
// expect-error: MS1000 5:1-5:2 unmatched closing delimiter '}'; remove it or add the matching opener before it
