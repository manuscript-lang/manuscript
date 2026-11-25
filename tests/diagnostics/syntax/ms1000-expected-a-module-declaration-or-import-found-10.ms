// conform: tags=diagnostics
// conform: phase=check
    view.%s(%s)
    if item.received { return panic("interface default %s") }
// expect-error: MS1000 3:5-3:9 expected a module declaration or import, found name 'view'; top level holds only import, constants (NAME := value), fn, type, enum, interface, and test (optionally prefixed by export), so put statements inside a fn
