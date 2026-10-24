# conform: tags=alternatives,maps,optional,records,stdlib-json,stdlib-net,testing,tier-io,try-result
# conform: phase=test
from "@std/testing.ms" import expect_equal
from "@std/json.ms" import parse, stringify, JsonError
from "@std/net.ms" import IpAddress, Cidr, parse_ip, parse_cidr

type Color:
    case Red
    case Green

type Palette:
    weights: Map[Color, Int]
    names: Map[Int, String]
    flags: Map[Bool, Int]

type Endpoint:
    host: IpAddress
    network: Cidr
    fallback: Optional[IpAddress]

test "JSON map keys named by payloadless case round-trip":
    var weights = Map[Color, Int]()
    weights.add(Color.Green, 2)
    weights.add(Color.Red, 1)
    var names = Map[Int, String]()
    names.add(1, "a")
    var flags = Map[Bool, Int]()
    flags.add(True, 1)
    let palette = Palette(weights, names, flags)
    let text = try stringify(palette)
    try expect_equal(text, "{\"weights\":{\"Green\":2,\"Red\":1},\"names\":{\"1\":\"a\"},\"flags\":{\"true\":1}}")
    let back = try parse[Palette](text)
    try expect_equal(try stringify(back), text)

test "JSON map keys reject an unknown case name":
    let invalid: Result[Map[Color, Int], JsonError] = error(JsonError.InvalidData)
    try expect_equal(parse[Map[Color, Int]]("{\"Blue\":1}"), invalid)
    try expect_equal(parse[Map[Color, Int]]("{\"Color.Red\":1}"), invalid)

test "JSON writes and reads IpAddress and Cidr as strings":
    let endpoint = Endpoint(try parse_ip("::1"), try parse_cidr("10.1.2.3/8"), some(try parse_ip("192.0.2.7")))
    let text = try stringify(endpoint)
    try expect_equal(text, "{\"host\":\"::1\",\"network\":\"10.0.0.0/8\",\"fallback\":\"192.0.2.7\"}")
    let back = try parse[Endpoint](text)
    try expect_equal(try stringify(back), text)

    let bare = try parse[Endpoint]("{\"host\":\"127.0.0.1\",\"network\":\"::/0\"}")
    try expect_equal(try stringify(bare), "{\"host\":\"127.0.0.1\",\"network\":\"::/0\"}")

test "JSON rejects malformed IpAddress and Cidr text":
    try expect_equal(parse[IpAddress]("\"999.1.1.1\"").is_error(), True)
    try expect_equal(parse[IpAddress]("1").is_error(), True)
    try expect_equal(parse[Cidr]("\"10.0.0.0/99\"").is_error(), True)
    try expect_equal(parse[Cidr]("null").is_error(), True)
