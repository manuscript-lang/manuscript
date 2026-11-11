// conform: tags=alternatives,optional,records,stdlib-json,stdlib-net,testing,tier-io,try-result
// conform: phase=test
import expect_equal, expect_error from "@std/test/test.ms"
import parse, stringify from "@std/data/json.ms"
import IpAddress, Cidr, parse_ip, parse_cidr from "@std/net/ip.ms"

enum Color:
    Red
    Green

type Swatch:
    color: Color
    shade: Color?

type Endpoint:
    host: IpAddress
    network: Cidr
    fallback: IpAddress?

test "JSON payloadless cases are their names and round-trip":
    swatch := Swatch(Color.Green, Color.Red)
    text := stringify(swatch)?
    expect_equal(text, "\{\"color\":\"Green\",\"shade\":\"Red\"\}")?

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

test "JSON writes and reads IpAddress and Cidr as strings":
    endpoint := Endpoint(
        parse_ip("::1")?, parse_cidr("10.1.2.3/8")?, parse_ip("192.0.2.7")?
    )
    text := stringify(endpoint)?
    expect_equal(
        text,
        "\{\"host\":\"::1\",\"network\":\"10.0.0.0/8\",\"fallback\":\"192.0.2.7\"\}"
    )?

    back := parse[Endpoint](text)?
    expect_equal(stringify(back)?, text)?

    bare := parse[Endpoint]("\{\"host\":\"127.0.0.1\",\"network\":\"::/0\"\}")?
    expect_equal(
        stringify(bare)?, "\{\"host\":\"127.0.0.1\",\"network\":\"::/0\"\}"
    )?

test "JSON rejects malformed IpAddress and Cidr text":
    expect_equal(parse[IpAddress]("\"999.1.1.1\"").is_error(), true)?
    expect_equal(parse[IpAddress]("1").is_error(), true)?
    expect_equal(parse[Cidr]("\"10.0.0.0/99\"").is_error(), true)?
    expect_equal(parse[Cidr]("null").is_error(), true)?
