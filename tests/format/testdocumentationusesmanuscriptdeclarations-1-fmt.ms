// conform: tags=formatter,interfaces,optional,parser,strings,tier-core,try-result
// conform: phase=parse
// conform: origin=pkg/checker/documentation_test.go:87 TestDocumentationUsesManuscriptDeclarations
interface DatagramSocket {
	fn address() String
	fn close() Void
	fn receive(max_bytes Int?, timeout Duration?) Datagram!
	fn send(data String, address String, timeout Duration?) Void!
	fn send_bytes(data Bytes, address String, timeout Duration?) Void!
}
// expect-format: rewritten
// expect-formatted: interface DatagramSocket {
// expect-formatted: \tfn address() String
// expect-formatted: \tfn close() Void
// expect-formatted: \tfn receive(max_bytes Int?, timeout Duration?) Datagram!
// expect-formatted: \tfn send(data, address String, timeout Duration?) Void!
// expect-formatted: \tfn send_bytes(data Bytes, address String, timeout Duration?) Void!
// expect-formatted: }
