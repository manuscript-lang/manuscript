// conform: tags=diagnostics
// conform: phase=check
name := apply(value: 1, transform: (item) => missing)
    name.to_string()
// expect-error: MS1000 4:5-4:9 expected a module declaration or import, found name 'name'; top level holds only import, constants (NAME := value), fn, type, enum, interface, and test (optionally prefixed by export), so put statements inside a fn
