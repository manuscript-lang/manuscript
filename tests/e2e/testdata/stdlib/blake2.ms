import blake2b, blake2s from "@std/data/blake2.ms"
import Bytes from "@std/bytes.ms"
import hex_encode from "@std/data/encoding.ms"
import expect_equal from "@std/test/test.ms"

test "BLAKE2b matches reference digests":
    try expect_equal(
        hex_encode(blake2b("abc".to_bytes())),
        "ba80a53f981c4d0d6a2797b69f12f6e94c212f14685ac4b74b12bb6fdbffa2d17d87c5392aab792dc252d5de4533cc9518d38aa8dbf1925ab92386edd4009923"
    )
    try expect_equal(
        hex_encode(blake2b(Bytes([]), length: 16)), "cae66941d9efbd404e4d88758ea67670"
    )
    try expect_equal(
        hex_encode(
            blake2b("abc".to_bytes(), key: "kkkkk".to_bytes(), length: 32)
        ),
        "bd03700094d907b2f4ced5d1b2c916d4abaccd60d122ff76e7fb4f1788bb84cb"
    )

test "BLAKE2b spans several blocks":
    var text = ""
    for index in 0..300:
        text += "x"
    try expect_equal(
        hex_encode(blake2b(text.to_bytes())),
        "fe42f4108dd98f9b4f19fb21f386dfbe9a860256176e0312a1f0de66a3aed2a5ed361a16f6128fe27b6c88d8f39eeaddca46f1c2c9357965f893d0a7d64bd1cb"
    )

test "BLAKE2s matches reference digests":
    var long = ""
    for index in 0..200:
        long += "x"
    try expect_equal(
        hex_encode(blake2s("abc".to_bytes())),
        "508c5e8c327c14e2e1a72ba34eeb452f37458b209ed63a294d999b4c86675982"
    )
    try expect_equal(
        hex_encode(
            blake2s("abc".to_bytes(), key: "kkkkk".to_bytes(), length: 20)
        ),
        "ba8dfdea05c35425cae0c4060fbb4822dc3e9494"
    )
    try expect_equal(
        hex_encode(blake2s(long.to_bytes())),
        "1b4e3b53c353aa90e148efe4699c5f60665a2cbc9ac60441d31d107ca6ee586a"
    )
    try expect_equal(
        hex_encode(blake2s(Bytes([]))),
        "69217a3079908094e11121d042354a7c1f55b6482ca1a51e1b250dfd1ed0eef9"
    )
