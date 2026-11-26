// conform: tags=diagnostics
// conform: phase=check
amount := key
    extra := y
    return counter.add(amount, extra)
// expect-error: MS1000 5:5-5:11 expected a module declaration or import, found 'return'; top level holds only import, constants (NAME := value), fn, type, enum, interface, and test (optionally prefixed by export), so put statements inside a fn
