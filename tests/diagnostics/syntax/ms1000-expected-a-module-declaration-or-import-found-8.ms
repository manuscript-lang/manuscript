// conform: tags=diagnostics
// conform: phase=check
callback := Callback(increment)
    callback | expect_equal(expected: callback)?
// expect-error: MS1000 4:5-4:13 expected a module declaration or import, found name 'callback'; top level holds only import, constants (NAME := value), fn, type, enum, interface, and test (optionally prefixed by export), so put statements inside a fn
