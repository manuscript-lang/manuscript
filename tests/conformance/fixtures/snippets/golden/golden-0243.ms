// conform: tags=diagnostics
// conform: phase=check
interface DatagramSocket:
    fn address() String
    fn close() Void
    fn receive(max_bytes: Int? = none, timeout: Duration? = none) Result[Datagram, NetworkError]
    fn send(data: String, address: String, timeout: Duration? = none) Result[Void, NetworkError]
    fn send_bytes(data: Bytes, address: String, timeout: Duration? = none) Result[Void, NetworkError]
