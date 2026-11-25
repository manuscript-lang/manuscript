// conform: tags=diagnostics
// conform: phase=check
interface DatagramSocket {
	fn address() String
	fn close() Void
	fn receive(
		max_bytes Int? = null,
		timeout Duration? = null,
	) Result[Datagram, NetworkError]
	fn send(
		data String,
		address String,
		timeout Duration? = null,
	) Result[Void, NetworkError]
	fn send_bytes(
		data Bytes,
		address String,
		timeout Duration? = null,
	) Result[Void, NetworkError]
}
// expect-error: MS2001 8:17 unknown type Duration; add: import Duration from "@std/time.ms"
// expect-fix: 1:1-1:1 "import Duration from \"@std/time.ms\"\n"
// expect-error: MS2001 9:14 unknown type Datagram; add: import Datagram from "@std/net/net.ms"
// expect-fix: 1:1-1:1 "import Datagram from \"@std/net/net.ms\"\n"
// expect-error: MS2001 9:24 unknown type NetworkError; declare it with 'type NetworkError:' / 'enum NetworkError:' / 'interface NetworkError:', declare it as a type parameter, or import it
// expect-error: MS2001 13:17 unknown type Duration; add: import Duration from "@std/time.ms"
// expect-fix: 1:1-1:1 "import Duration from \"@std/time.ms\"\n"
// expect-error: MS2001 14:20 unknown type NetworkError; declare it with 'type NetworkError:' / 'enum NetworkError:' / 'interface NetworkError:', declare it as a type parameter, or import it
// expect-error: MS2001 16:14 unknown type Bytes; add: import Bytes from "@std/bytes.ms"
// expect-fix: 1:1-1:1 "import Bytes from \"@std/bytes.ms\"\n"
// expect-error: MS2001 18:17 unknown type Duration; add: import Duration from "@std/time.ms"
// expect-fix: 1:1-1:1 "import Duration from \"@std/time.ms\"\n"
// expect-error: MS2001 19:20 unknown type NetworkError; declare it with 'type NetworkError:' / 'enum NetworkError:' / 'interface NetworkError:', declare it as a type parameter, or import it
