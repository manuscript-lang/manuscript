# conform: tags=formatter,interfaces,optional,parser,strings,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/checker/documentation_test.go:87 TestDocumentationUsesManuscriptDeclarations
interface DatagramSocket:
    fn address() String
    fn close() Unit
    fn receive(max_bytes: Int?, timeout: Duration?) Datagram!NetworkError
    fn send(data: String, address: String, timeout: Duration?) Unit!NetworkError
    fn send_bytes(data: Bytes, address: String, timeout: Duration?) Unit!NetworkError
