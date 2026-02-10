// @test: Stdlib Network - fetch and fetch_stream from std/network

import { fetch, fetch_stream, FetchResponse, FetchStreamResponse } from "std/network"
import { resolve } from "std/concurrency"

let res: FetchResponse = resolve(fetch("https://httpbin.org/get"))
// @expect: 200
print(res.status)
// @expect: true
print(matches(res.body, "httpbin"))

let streamRes: FetchStreamResponse = resolve(fetch_stream("https://httpbin.org/get"))
// @expect: 200
print(streamRes.status)
var streamBody = ""
for chunk in streamRes.body
  streamBody = streamBody + chunk
// @expect: true
print(matches(streamBody, "httpbin"))
