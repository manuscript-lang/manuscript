// conform: tags=diagnostics
// conform: phase=check
interface ${1:Name} {
    ${0:fn operation() Void}
}
// expect-error: MS1000 3:11-3:12 unexpected source character '$'; this character is not part of Manuscript's syntax outside text
// expect-error: MS1000 5:1-5:2 unmatched closing delimiter '}'; remove it or add the matching opener before it
