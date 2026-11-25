// conform: tags=diagnostics
// conform: phase=check
 = read_hex4()
fn after() Void => void
// expect-error: MS1000 3:2-3:3 expected a module declaration or import, found '='; top level holds only import, constants (NAME := value), fn, type, enum, interface, and test (optionally prefixed by export), so put statements inside a fn
