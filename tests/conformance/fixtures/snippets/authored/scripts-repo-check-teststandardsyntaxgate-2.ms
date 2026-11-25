// conform: tags=diagnostics,formatter,interfaces,records,tier-core
// conform: phase=check,parse
// conform: origin=scripts/repo-check/main_test.go:43 TestStandardSyntaxGate
type Data {
	count Int = 3
}

fn Data.read() Int { ... }
// expect-error: MS3000 8:9 reachable fallthrough in function returning Int; end every path with 'return <Int>' (or make the last branch return)
