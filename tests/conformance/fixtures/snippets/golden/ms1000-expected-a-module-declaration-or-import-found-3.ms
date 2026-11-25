// conform: tags=diagnostics
// conform: phase=check
  --debug               Alias for --build-type Debug
  --watch               Rebuild and restart after each saved source change
  --cpu-profile <path>  Write a CPU profile
  --heap-profile <path> Write a heap profile
  --trace <path>        Write an execution trace
// expect-error: MS1000 3:3-3:4 expected a module declaration or import, found '-'; top level holds only import, constants (NAME := value), fn, type, enum, interface, and test (optionally prefixed by export), so put statements inside a fn
