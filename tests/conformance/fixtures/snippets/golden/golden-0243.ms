// conform: tags=diagnostics
// conform: phase=check
interface DatagramSocket:
    fn address() String
    fn close() Void
    fn receive(max_bytes Int? = null, timeout Duration? = null) Result[Datagram, NetworkError]
    fn send(data String, address String, timeout Duration? = null) Result[Void, NetworkError]
    fn send_bytes(data Bytes, address String, timeout Duration? = null) Result[Void, NetworkError]
