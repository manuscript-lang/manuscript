// conform: tags=alternatives,optional,records,stdlib-json,stdlib-net,testing,tier-io,try-result
// conform: phase=test
import expect_equal, expect_error from "@std/test/test.ms"
import parse, stringify from "@std/data/json.ms"
import IpAddress, Cidr, parse_ip, parse_cidr from "@std/net/ip.ms"

enum Color:
    Red
    Green

type Swatch:
    color Color
    shade Color?

type Endpoint:
    host IpAddress
    network Cidr
    fallback IpAddress?

test "JSON payloadless cases are their names and round-trip":
    swatch := Swatch(Color.Green, Color.Red)
    text := stringify(swatch)?
    expect_equal(text, "{\"color\":\"Green\",\"shade\":\"Red\"}")?

    back := parse[Swatch](text)?
    expect_equal(stringify(back)?, text)?

test "JSON rejects an unknown case name":
    expect_equal(
        (expect_error(parse[Color]("\"Blue\""))?).kind, "EBADMSG"
    )?
    expect_equal(
        (expect_error(parse[Color]("\"Color.Red\""))?).kind,
        "EBADMSG"
    )?

test "JSON writes IpAddress and Cidr as strings":
    endpoint := Endpoint(
        parse_ip("::1")?, parse_cidr("10.1.2.3/8")?, parse_ip("192.0.2.7")?
    )
    expect_equal(
        stringify(endpoint)?,
        "{\"host\":\"::1\",\"network\":\"10.0.0.0/8\",\"fallback\":\"192.0.2.7\"}"
    )?

    bare := Endpoint(parse_ip("127.0.0.1")?, parse_cidr("::/0")?, null)
    expect_equal(
        stringify(bare)?, "{\"host\":\"127.0.0.1\",\"network\":\"::/0\"}"
    )?
