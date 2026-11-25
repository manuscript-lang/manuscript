// conform: tags=diagnostics
// conform: phase=check
values.add(1, 2)
    found := values.get(1)
    present := values.contains(1)
    size := values.length()
// expect-error: MS1000 3:1-3:7 expected a module declaration or import, found name 'values'; top level holds only import, constants (NAME := value), fn, type, enum, interface, and test (optionally prefixed by export), so put statements inside a fn
