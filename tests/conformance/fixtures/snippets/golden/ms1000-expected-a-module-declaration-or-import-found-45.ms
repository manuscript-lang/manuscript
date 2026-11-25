// conform: tags=diagnostics
// conform: phase=check
replace := "a".replace_n
    replace("a", "b")
// expect-error: MS1000 4:5-4:12 expected a module declaration or import, found name 'replace'; top level holds only import, constants (NAME := value), fn, type, enum, interface, and test (optionally prefixed by export), so put statements inside a fn
