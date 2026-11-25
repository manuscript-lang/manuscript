// conform: tags=diagnostics,records,strings,tier-core
// conform: phase=check
// conform: origin=pkg/checker/documentation_test.go:88 TestDocumentationUsesManuscriptDeclarations
type DnsRecord {
	kind DnsKind
	value String
	priority Int
	weight Int
	port Int
}
// expect-error: MS2001 5:10 unknown type DnsKind; add: import DnsKind from "@std/net/ip.ms"
// expect-fix: 1:1-1:1 "import DnsKind from \"@std/net/ip.ms\"\n"
