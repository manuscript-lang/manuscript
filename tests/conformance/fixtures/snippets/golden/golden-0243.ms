// conform: tags=diagnostics
// conform: phase=check
interface DatagramSocket:
    fn address() String
    fn close() Unit
    fn receive(max_bytes: Int? = none, timeout: Duration? = none) Result[Datagram, NetworkError]
    fn send(data: String, address: String, timeout: Duration? = none) Result[Unit, NetworkError]
    fn send_bytes(data: Bytes, address: String, timeout: Duration? = none) Result[Unit, NetworkError]
