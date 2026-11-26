// conform: tags=diagnostics
// conform: phase=check
    o: Int? = null
    v := o.get(3)
// expect-error: MS1000 3:6-3:7 remove the ':' between 'o' and its type; write o Type
// expect-fix: 3:6-3:7 ""
