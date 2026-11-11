// Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
// expect-mir: "drop"

import (
	HttpHeaders, HttpMethod, headers from "@std/net/http.ms",
	RequestOptions, request from "@std/net/net.ms",
)

fn hs() Result[HttpHeaders, Error]: return ok(headers())

fn one() Result[String, Error]: return ok("b")

fn go(n: Int) Result[Int, Error]:
	_r := request(
		method: HttpMethod.Get, url: "http://x/{n}",
		options: RequestOptions(headers: (hs()?))
	)
	_s := "abc {n}".replace("a", (one()?))
	return ok(0)

fn main() Unit:
	_r := go(1)
