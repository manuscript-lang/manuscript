// conform: tags=diagnostics
// conform: phase=check
fn ${1:name}(${2}) ${3:Void} {
    ${0:return}
}
// expect-error: MS1000 3:4-3:5 unexpected source character '$'; this character is not part of Manuscript's syntax outside text
// expect-error: MS1000 5:1-5:2 unmatched closing delimiter '}'; remove it or add the matching opener before it
