// conform: tags=diagnostics
// conform: phase=check
Usage: ms <command> [arguments] [options]
       ms help [command]

Manuscript checks, builds, and runs .ms source and ms.toml projects.

Commands:
  check          Parse and type-check without executing
  lint           Check source hygiene and semantic lint rules
  build          Build a native executable
  emit           Emit standalone Go source with the runtime
  run            Build and run an application
  test           Execute test blocks, including imported modules
  fmt            Format source files or a project
  verify         Run check, fmt --check, lint, and test; one result
  inspect        Emit checked source metadata as JSON
  diagram        Emit a static call graph as ascii or Mermaid
  review         Report where to look: project map, or the semantic effect of a diff
  profile        Run with CPU and heap capture; optionally trace
  pprof          Inspect captured CPU or heap profiles
  trace          Inspect captured execution traces
  debug          Start an application in the embedded Delve debugger
  dap            Serve one native debugger session on stdin/stdout
  init           Create a new project with a manifest, entry, test, and .gitignore
  lsp            Serve the language server on stdin/stdout
  search_symbol  Find a project or standard-library symbol: definition, type, uses
  guide          Print the language cheat sheet
  help           Show help for a command
  version        Print the compiler version

Options:
  -h, --help  Show help
  --version   Print the compiler version

Native build levels:
  --build-type <Debug|Release|RelWithDebInfo|MinSizeRel>
  Default: Release; profile and profiled tests default to RelWithDebInfo; debug always uses Debug

Start with:
  ms init hello
  ms check ms.toml
  ms run ms.toml -- first second

Bare ms prints this help and exits successfully.
Long options that take values also accept --flag=value.
Run 'ms help <command>' or 'ms <command> --help' for usage and examples.
The Go toolchain is embedded and cannot be replaced by external tools.
MANUSCRIPT_CACHE_DIR selects the user cache for bundled toolchains
and standalone run/test/debug/profile artifacts.
