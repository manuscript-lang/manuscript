// conform: tags=diagnostics
// conform: phase=check
    empty: List[Int] = []
// expect-error: MS1000 3:10-3:11 remove the ':' between 'empty' and its type; write empty Type
// expect-fix: 3:10-3:11 ""
