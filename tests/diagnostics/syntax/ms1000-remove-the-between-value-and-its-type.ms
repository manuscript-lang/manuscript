// conform: tags=diagnostics
// conform: phase=check
    read := fn(value: Shape = shapes.get(0)) Shape => value
    var sum
// expect-error: MS1000 3:21-3:22 remove the ':' between 'value' and its type; write value Type
// expect-fix: 3:21-3:22 ""
