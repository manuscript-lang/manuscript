# conform: tags=modules,parser,stdlib-http,tier-io
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/completion_test.go:267 TestExpandedStandardMembersAndInterfaceSnippet
import HttpClient from "@std/http.ms"
fn work(client: HttpClient) Unit:
    client.|
