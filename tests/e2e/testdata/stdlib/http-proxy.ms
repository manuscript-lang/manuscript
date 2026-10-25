from "@std/http.ms" import Request, client_info, headers, HttpError
from "@std/net.ms" import parse_cidr
from "@std/testing.ms" import expect_equal, expect_true

test "untrusted peers cannot spoof client identity or scheme":
    let fields = headers()
    try fields.append("X-Forwarded-For", "not an address".to_bytes())
    try fields.append("X-Forwarded-Proto", "https, evil".to_bytes())

    let info = try client_info(
        Request(peer_address: "192.0.2.4:9", scheme: "http", headers: fields)
    )
    try expect_equal(info.address.text(), "192.0.2.4")
    try expect_equal(info.scheme, "http")
    try expect_true(not info.forwarded)

test "trusted chain stops at first untrusted address and preserves repeated field order":
    let fields = headers()
    try fields.append("X-Forwarded-For", "198.51.100.99, 203.0.113.7".to_bytes())
    try fields.append("X-Forwarded-For", "10.1.2.3".to_bytes())
    try fields.append("X-Forwarded-Proto", "https".to_bytes())

    let request = Request(
        peer_address: "[::ffff:10.0.0.1]:8080", scheme: "http", headers: fields
    )
    let info = try client_info(request, [try parse_cidr("10.0.0.0/8")])
    try expect_equal(info.address.text(), "203.0.113.7")
    try expect_equal(info.scheme, "https")
    try expect_equal(request.scheme, "http")
    try expect_true(info.forwarded)

test "trusted proxy metadata rejects ambiguous schemes and bounded malformed chains":
    let trusted = [try parse_cidr("127.0.0.0/8")]

    for value in ["https,http", "ftp", ""]:
        let fields = headers()
        try fields.append("X-Forwarded-Proto", value.to_bytes())

        let result = client_info(
            Request(peer_address: "127.0.0.1:1", headers: fields), trusted
        )
        try expect_equal(result.err(), HttpError.InvalidInput)

    for value in [
        "example.com", "user@192.0.2.1", "192.0.2.1:80", "fe80::1%eth0", "192.0.2.1,"
    ]:
        let fields = headers()
        try fields.append("X-Forwarded-For", value.to_bytes())

        let result = client_info(
            Request(peer_address: "127.0.0.1:1", headers: fields), trusted
        )
        try expect_equal(result.err(), HttpError.InvalidInput)

    let fields = headers()
    try fields.append("X-Forwarded-For", "192.0.2.1,192.0.2.2".to_bytes())

    let request = Request(peer_address: "127.0.0.1:1", headers: fields)
    try expect_equal(
        client_info(request, trusted, max_forwarded_hops: 1).err(),
        HttpError.LimitExceeded
    )
    try expect_equal(
        client_info(request, trusted, max_forwarded_bytes: 3).err(),
        HttpError.LimitExceeded
    )
