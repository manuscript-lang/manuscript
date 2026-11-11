// conform: tags=diagnostics
// conform: phase=check
test %q:
    bytes := Bytes(values: [0, 255])
    list := [0, 1]
%s