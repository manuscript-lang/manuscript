// conform: tags=diagnostics
// conform: phase=check
import HttpClient from "@std/net/http.ms"
fn work(client HttpClient) Void {
    client.|
}
// expect-error: MS1000 5:12-5:13 expected a name, found '|'
