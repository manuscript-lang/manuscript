# Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
# expect-mir: "drop"

import headers, HttpHeaders, HttpMethod from "@std/http.ms"
import request from "@std/net.ms"

fn hs() Result[HttpHeaders, Error]: return ok(headers())

fn one() Result[String, Error]: return ok("b")

fn go(n: Int) Result[Int, Error]:
    let _r = request(
        method: HttpMethod.Get, url: "http://x/{n}", headers: (try hs()), body: ""
    )
    let _s = "abc {n}".replace("a", (try one()))
    return ok(0)

export fn main() Int:
    let _r = go(1)
    return 0
