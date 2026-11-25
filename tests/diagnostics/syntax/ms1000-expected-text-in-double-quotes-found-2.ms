// conform: tags=diagnostics
// conform: phase=check
test %q {
    bytes := Bytes(values: [0, 255])
    list := [0, 1]
}
%s
// expect-error: MS1000 3:6-3:7 expected text in double quotes, found '%'
// expect-error: MS1000 7:1-7:2 expected a module declaration or import, found '%'; top level holds only import, constants (NAME := value), fn, type, enum, interface, and test (optionally prefixed by export), so put statements inside a fn
