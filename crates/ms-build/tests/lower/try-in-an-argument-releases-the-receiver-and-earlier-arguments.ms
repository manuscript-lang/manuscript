// Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
// expect-mir: "drop"

import headers, HttpHeaders, HttpMethod from "@std/net/http.ms"
import RequestOptions, request from "@std/net/net.ms"

fn hs() Result[HttpHeaders, Error]: return ok(headers())

fn one() Result[String, Error]: return ok("b")

fn go(n: Int) Result[Int, Error]:
    let _r = request(
        method: HttpMethod.Get, url: "http://x/{n}",
        options: RequestOptions(headers: (try hs()))
    )
    let _s = "abc {n}".replace("a", (try one()))
    return ok(0)

fn main() Unit:
    let _r = go(1)
