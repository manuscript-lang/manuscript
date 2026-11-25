// conform: tags=diagnostics
// conform: phase=check
native fn commands() Commands
// expect-error: MS1000 3:1-3:7 expected a module declaration or import, found name 'native'; top level holds only import, constants (NAME := value), fn, type, enum, interface, and test (optionally prefixed by export), so put statements inside a fn
