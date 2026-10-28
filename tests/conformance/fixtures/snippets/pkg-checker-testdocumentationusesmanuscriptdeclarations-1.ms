# conform: tags=diagnostics,interfaces,optional,strings,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/checker/documentation_test.go:87 TestDocumentationUsesManuscriptDeclarations
interface DatagramSocket:
    fn address() String
    fn close() Unit
    fn receive(
        max_bytes: Optional[Int] = none,
        timeout: Optional[Duration] = none
    ) Result[Datagram, NetworkError]
    fn send(
        data: String,
        address: String,
        timeout: Optional[Duration] = none
    ) Result[Unit, NetworkError]
    fn send_bytes(
        data: Bytes,
        address: String,
        timeout: Optional[Duration] = none
    ) Result[Unit, NetworkError]
