// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/guide/guide_test.go:33 TestCheatsheetClaimsMatchTheCompiler
export fn main() Int { ... }
// expect-error: MS3000 4:8 reachable fallthrough in function returning Int; end every path with 'return <Int>' (or make the last branch return)
