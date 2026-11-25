// conform: tags=diagnostics
// conform: phase=check
    return out
fn probe() Int {
    shapes := [Shape.C0(1)]
    return area(shapes.get(0))
}
// expect-error: MS1000 3:5-3:11 expected a module declaration or import, found 'return'; top level holds only import, constants (NAME := value), fn, type, enum, interface, and test (optionally prefixed by export), so put statements inside a fn
