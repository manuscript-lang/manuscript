// conform: tags=diagnostics
// conform: phase=check
queue := Queue[Int](capacity: 2)
    queue.close()
// expect-error: MS1000 4:5-4:10 expected a module declaration or import, found name 'queue'; top level holds only import, constants (NAME := value), fn, type, enum, interface, and test (optionally prefixed by export), so put statements inside a fn
