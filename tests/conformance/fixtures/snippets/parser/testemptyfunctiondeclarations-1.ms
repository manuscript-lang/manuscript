// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/parser/empty_declarations_test.go:10 TestEmptyFunctionDeclarations
export fn commands() Commands { ... }
// expect-error: MS2001 4:22 unknown type Commands; add: import Commands from "@std/os/process.ms"
// expect-fix: 1:1-1:1 "import Commands from \"@std/os/process.ms\"\n"
