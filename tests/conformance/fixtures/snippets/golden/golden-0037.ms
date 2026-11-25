// conform: tags=diagnostics
// conform: phase=check
ms build ms.toml -o hello
  ms build main.ms --build-type MinSizeRel
// expect-error: MS1000 3:1-3:3 expected a module declaration or import, found name 'ms'; top level holds only import, constants (NAME := value), fn, type, enum, interface, and test (optionally prefixed by export), so put statements inside a fn
