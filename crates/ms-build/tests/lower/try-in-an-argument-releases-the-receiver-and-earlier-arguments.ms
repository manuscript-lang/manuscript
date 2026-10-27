# Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
# expect-mir: "drop"

from "@std/http.ms" import headers, HttpHeaders, HttpMethod
from "@std/net.ms" import network

def hs() -> Result[HttpHeaders, Error]: return ok(headers())

def one() -> Result[String, Error]: return ok("b")

def go(n: Int) -> Result[Int, Error]:
    let _r = network().request(method: HttpMethod.Get, url: f"http://x/{n}", headers: (try hs()), body: "")
    let _s = f"abc {n}".replace("a", (try one()))
    return ok(0)

export def main() -> Int:
    let _r = go(1)
    return 0
