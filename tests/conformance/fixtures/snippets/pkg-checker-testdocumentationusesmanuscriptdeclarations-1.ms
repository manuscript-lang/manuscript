# conform: tags=diagnostics,interfaces,optional,strings,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/checker/documentation_test.go:87 TestDocumentationUsesManuscriptDeclarations
interface DatagramSocket:
    def address() -> String
    def close() -> Unit
    def receive(
        max_bytes: Optional[Int] = none,
        timeout: Optional[Duration] = none
    ) -> Result[Datagram, NetworkError]
    def send(
        data: String,
        address: String,
        timeout: Optional[Duration] = none
    ) -> Result[Unit, NetworkError]
    def send_bytes(
        data: Bytes,
        address: String,
        timeout: Optional[Duration] = none
    ) -> Result[Unit, NetworkError]
