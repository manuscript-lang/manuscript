// conform: tags=formatter,parser,records,strings,tier-core
// conform: phase=parse
// conform: origin=pkg/checker/documentation_test.go:88 TestDocumentationUsesManuscriptDeclarations
type DnsRecord {
	kind DnsKind
	value String
	priority Int
	weight Int
	port Int
}
// expect-format: rewritten
// expect-formatted: type DnsRecord {
// expect-formatted: \tkind DnsKind
// expect-formatted: \tvalue String
// expect-formatted: \tpriority, weight, port Int
// expect-formatted: }
