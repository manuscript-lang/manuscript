// conform: tags=diagnostics
// conform: phase=check
f := forward(base64_encode)
    f(Bytes([]))
// expect-error: MS1000 4:5-4:6 expected a module declaration or import, found name 'f'; top level holds only import, constants (NAME := value), fn, type, enum, interface, and test (optionally prefixed by export), so put statements inside a fn
