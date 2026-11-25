// conform: tags=diagnostics
// conform: phase=check
    n := 1
    n = 2
// expect-error: MS1000 4:5-4:6 expected a module declaration or import, found name 'n'; top level holds only import, constants (NAME := value), fn, type, enum, interface, and test (optionally prefixed by export), so put statements inside a fn
