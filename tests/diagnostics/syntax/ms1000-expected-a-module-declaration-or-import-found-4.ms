// conform: tags=diagnostics
// conform: phase=check
  --build-type <level>  Debug, Release, RelWithDebInfo, or MinSizeRel (case-insensitive)
// expect-error: MS1000 3:3-3:4 expected a module declaration or import, found '-'; top level holds only import, constants (NAME := value), fn, type, enum, interface, and test (optionally prefixed by export), so put statements inside a fn
