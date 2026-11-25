// conform: tags=diagnostics
// conform: phase=check
result := cell.bump(1)
        i += 1
// expect-error: MS1000 4:9-4:10 expected a module declaration or import, found name 'i'; top level holds only import, constants (NAME := value), fn, type, enum, interface, and test (optionally prefixed by export), so put statements inside a fn
