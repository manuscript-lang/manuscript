// conform: tags=diagnostics
// conform: phase=check
{key, value} := entry
        label: Int = key
// expect-error: MS1000 3:1-3:2 expected a module declaration or import, found '{'; top level holds only import, constants (NAME := value), fn, type, enum, interface, and test (optionally prefixed by export), so put statements inside a fn
