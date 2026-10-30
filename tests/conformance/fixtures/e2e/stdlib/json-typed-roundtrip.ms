# conform: tags=alternatives,optional,records,stdlib-json,stdlib-net,testing,tier-io,try-result
# conform: phase=test
import expect_equal from "@std/test.ms"
import parse, stringify, JsonError from "@std/json.ms"
import IpAddress, Cidr, parse_ip, parse_cidr from "@std/net.ms"

type Color:
    case Red
    case Green

type Swatch:
    color: Color
    shade: Optional[Color]

type Endpoint:
    host: IpAddress
    network: Cidr
    fallback: Optional[IpAddress]

test "JSON payloadless cases are their names and round-trip":
    let swatch = Swatch(Color.Green, some(Color.Red))
    let text = try stringify(swatch)
    try expect_equal(text, "\{\"color\":\"Green\",\"shade\":\"Red\"\}")

    let back = try parse[Swatch](text)
    try expect_equal(try stringify(back), text)

test "JSON rejects an unknown case name":
    let invalid: Result[Color, JsonError] = error(JsonError.InvalidData)
    try expect_equal(parse[Color]("\"Blue\""), invalid)
    try expect_equal(parse[Color]("\"Color.Red\""), invalid)

test "JSON writes and reads IpAddress and Cidr as strings":
    let endpoint = Endpoint(
        try parse_ip("::1"), try parse_cidr("10.1.2.3/8"),
        some(try parse_ip("192.0.2.7"))
    )
    let text = try stringify(endpoint)
    try expect_equal(
        text,
        "\{\"host\":\"::1\",\"network\":\"10.0.0.0/8\",\"fallback\":\"192.0.2.7\"\}"
    )

    let back = try parse[Endpoint](text)
    try expect_equal(try stringify(back), text)

    let bare = try parse[Endpoint]("\{\"host\":\"127.0.0.1\",\"network\":\"::/0\"\}")
    try expect_equal(
        try stringify(bare), "\{\"host\":\"127.0.0.1\",\"network\":\"::/0\"\}"
    )

test "JSON rejects malformed IpAddress and Cidr text":
    try expect_equal(parse[IpAddress]("\"999.1.1.1\"").is_error(), true)
    try expect_equal(parse[IpAddress]("1").is_error(), true)
    try expect_equal(parse[Cidr]("\"10.0.0.0/99\"").is_error(), true)
    try expect_equal(parse[Cidr]("null").is_error(), true)
