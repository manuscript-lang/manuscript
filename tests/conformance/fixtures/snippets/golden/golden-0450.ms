// conform: tags=diagnostics
// conform: phase=check
names := [1, 2].map((item) => missing)
    names.join(",")
// expect-error: MS1000 4:5-4:10 expected a module declaration or import, found name 'names'; top level holds only import, constants (NAME := value), fn, type, enum, interface, and test (optionally prefixed by export), so put statements inside a fn
