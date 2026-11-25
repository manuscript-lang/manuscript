// conform: tags=diagnostics
// conform: phase=check
test "${1:name}" {
    ${0:return}
}
// expect-error: MS1000 4:5-4:6 unexpected source character '$'; this character is not part of Manuscript's syntax outside text
