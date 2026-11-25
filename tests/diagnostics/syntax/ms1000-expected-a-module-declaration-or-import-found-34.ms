// conform: tags=diagnostics
// conform: phase=check
if found := affine(peer) {
            sum += found
        peer += 1
}
// expect-error: MS1000 3:1-3:3 expected a module declaration or import, found 'if'; top level holds only import, constants (NAME := value), fn, type, enum, interface, and test (optionally prefixed by export), so put statements inside a fn
