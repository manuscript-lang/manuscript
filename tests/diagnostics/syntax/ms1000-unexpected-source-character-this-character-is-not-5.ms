// conform: tags=diagnostics
// conform: phase=check
if let ${1:value} = ${2:optional} {
    $0
}
// expect-error: MS1000 3:8-3:9 unexpected source character '$'; this character is not part of Manuscript's syntax outside text
// expect-error: MS1000 5:1-5:2 unmatched closing delimiter '}'; remove it or add the matching opener before it
