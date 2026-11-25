// conform: tags=diagnostics
// conform: phase=check
for entry in values {
        key := entry.key
}
// expect-error: MS1000 3:1-3:4 expected a module declaration or import, found 'for'; top level holds only import, constants (NAME := value), fn, type, enum, interface, and test (optionally prefixed by export), so put statements inside a fn
