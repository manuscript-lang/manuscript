// conform: tags=diagnostics
// conform: phase=check
read := fn() Int => sum
    sum = 0
// expect-error: MS1000 4:5-4:8 expected a module declaration or import, found name 'sum'; top level holds only import, constants (NAME := value), fn, type, enum, interface, and test (optionally prefixed by export), so put statements inside a fn
