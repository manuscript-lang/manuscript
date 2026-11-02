# conform: tags=formatter,parser,records,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/documentation_test.go:88 TestDocumentationUsesManuscriptDeclarations
type DnsRecord:
    kind: DnsKind
    value: String
    priority: Int
    weight: Int
    port: Int
