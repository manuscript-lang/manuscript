// conform: tags=diagnostics,interfaces,optional,strings,tier-core,try-result
// conform: phase=check
// conform: origin=pkg/checker/documentation_test.go:87 TestDocumentationUsesManuscriptDeclarations
interface DatagramSocket {
	fn address() String
	fn close() Void
	fn receive(max_bytes Int?, timeout Duration?) Datagram!
	fn send(data String, address String, timeout Duration?) Void!
	fn send_bytes(data Bytes, address String, timeout Duration?) Void!
}
// expect-error: MS2001 7:40 unknown type Duration; add: import Duration from "@std/time.ms"
// expect-fix: 1:1-1:1 "import Duration from \"@std/time.ms\"\n"
// expect-error: MS2001 7:51 unknown type Datagram; add: import Datagram from "@std/net/net.ms"
// expect-fix: 1:1-1:1 "import Datagram from \"@std/net/net.ms\"\n"
// expect-error: MS2001 8:50 unknown type Duration; add: import Duration from "@std/time.ms"
// expect-fix: 1:1-1:1 "import Duration from \"@std/time.ms\"\n"
// expect-error: MS2001 9:24 unknown type Bytes; add: import Bytes from "@std/bytes.ms"
// expect-fix: 1:1-1:1 "import Bytes from \"@std/bytes.ms\"\n"
// expect-error: MS2001 9:55 unknown type Duration; add: import Duration from "@std/time.ms"
// expect-fix: 1:1-1:1 "import Duration from \"@std/time.ms\"\n"
