// conform: tags=diagnostics
// conform: phase=check
if line := read_line(input) {
        size := line.get().length()
        return size > 0
    return false
}
// expect-error: MS1000 3:1-3:3 expected a module declaration or import, found 'if'; top level holds only import, constants (NAME := value), fn, type, enum, interface, and test (optionally prefixed by export), so put statements inside a fn
