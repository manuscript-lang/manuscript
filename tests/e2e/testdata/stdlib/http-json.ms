from "@std/http.ms" import Request, RequestDecodeError, decode_json, headers
from "@std/streams.ms" import from_bytes
from "@std/json.ms" import JsonLimits
from "@std/testing.ms" import expect_equal, expect_true

type Payload:
    name: String
    count: Int

def request(body: String, media: String = "application/json") -> Request:
    let fields = headers()
    fields.append("Content-Type", media.to_bytes()).get()
    return Request(headers: fields, body: from_bytes(body.to_bytes()))

test "JSON requests distinguish media syntax and shape errors":
    try expect_equal(
        decode_json[Payload](request("{}", "text/plain")).err(),
        RequestDecodeError.UnsupportedMediaType
    )
    try expect_equal(
        decode_json[Payload](request("{")).err(), RequestDecodeError.MalformedJson
    )
    try expect_equal(
        decode_json[Payload](request("{}")).err(), RequestDecodeError.InvalidValue
    )

    let decoded = try decode_json[Payload](
        request(
            "{\"name\":\"Ada\",\"count\":3}", "application/problem+json; charset=UTF-8"
        )
    )
    try expect_equal(decoded.name, "Ada")
    try expect_equal(decoded.count, 3)

test "JSON request decoding rejects unknown fields and applies explicit limits":
    let extra = "{\"name\":\"Ada\",\"count\":3,\"extra\":true}"
    try expect_equal(
        decode_json[Payload](request(extra)).err(), RequestDecodeError.InvalidValue
    )

    let allowed = try decode_json[Payload](request(extra), ignore_unknown_fields: True)
    try expect_equal(allowed.count, 3)
    try expect_true(
        decode_json[Payload](
            request(extra), JsonLimits(max_bytes: 4)
        ).is_error()
    )
    try expect_true(
        decode_json[Payload](
            request(extra), JsonLimits(max_values: 1)
        ).is_error()
    )
