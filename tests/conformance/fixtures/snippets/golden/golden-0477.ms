// conform: tags=diagnostics
// conform: phase=check
encode := forward(CompressionFormat.Gzip.compress)
    encode("".to_bytes())
// expect-error: MS1000 4:5-4:11 expected a module declaration or import, found name 'encode'; top level holds only import, constants (NAME := value), fn, type, enum, interface, and test (optionally prefixed by export), so put statements inside a fn
