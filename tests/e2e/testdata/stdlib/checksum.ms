import crc32 from "@std/data/checksum.ms"
import Bytes, BytesBuilder from "@std/bytes.ms"
import bit_xor, shift_right_unsigned from "@std/math/math.ms"
import expect_equal from "@std/test/test.ms"

# A bit-at-a-time oracle deliberately independent of the production byte table.
fn reference(data: Bytes) UInt32:
    var crc = 4294967295

    for index in 0..data.length():
        crc = bit_xor(crc, data.get(index).to_int())

        for bit in 0..8:
            let low = crc % 2
            crc = shift_right_unsigned(crc, 1)
            if low == 1:
                crc = bit_xor(crc, 3988292384)

    return bit_xor(crc, 4294967295).to_uint32().get(0)

test "IEEE CRC32 known text vectors retain unsigned results":
    try expect_equal(crc32(Bytes([])).to_int(), 0)
    try expect_equal(crc32("123456789".to_bytes()).to_int(), 3421780262)
    try expect_equal(crc32("a".to_bytes()).to_int(), 3904355907)
    try expect_equal(crc32("abc".to_bytes()).to_int(), 891568578)
    try expect_equal(crc32("message digest".to_bytes()).to_int(), 538287487)
    try expect_equal(
        crc32(
            "The quick brown fox jumps over the lazy dog".to_bytes()
        ).to_int(),
        1095738169
    )

test "IEEE CRC32 covers every binary byte and sliced inputs":
    var builder = BytesBuilder()
    for byte in 0..256:
        builder.append(byte.to_uint8().get(0))

    let data = builder.build()
    try expect_equal(crc32(data).to_int(), 688229491)
    try expect_equal(crc32(Bytes([0])).to_int(), 3523407757)
    try expect_equal(crc32(Bytes([255])).to_int(), 4278190080)

    let view = try data.slice(17, 241)
    try expect_equal(crc32(view), reference(view))

    let empty = try data.slice(128, 128)
    try expect_equal(crc32(empty).to_int(), 0)
    try expect_equal(data.length(), 256)
    try expect_equal(data.get(17).to_int(), 17)

test "IEEE CRC32 matches bit oracle across byte and length boundaries":
    var builder = BytesBuilder()
    for index in 0..513:
        builder.append(((index * 73 + index / 7) % 256).to_uint8().get(0))

    let data = builder.build()

    for length in [1, 2, 3, 4, 7, 8, 9, 15, 16, 17, 31, 32, 33, 255, 256, 257, 512, 513]:
        let prefix = try data.slice(0, length)
        try expect_equal(crc32(prefix), reference(prefix))

    # Repeated calls do not retain state or depend on a previous input.
    try expect_equal(crc32(data), crc32(data))
    try expect_equal(crc32("123456789".to_bytes()).to_int(), 3421780262)

test "IEEE CRC32 appending its little endian checksum gives the standard residue":
    let data = "123456789".to_bytes()
    var builder = BytesBuilder()
    builder.append_bytes(data)
    builder.append_uint32_le(crc32(data))
    try expect_equal(crc32(builder.build()).to_int(), 558161692)

test "IEEE CRC32 large binary vector":
    var builder = BytesBuilder()
    for index in 0..1048576:
        builder.append(((index * 73 + index / 7) % 256).to_uint8().get(0))

    let data = builder.build()
    try expect_equal(crc32(data).to_int(), 9350483)

    # Short views use the same IEEE convention.
    try expect_equal(crc32(try data.slice(0, 31)).to_int(), 2164364862)
    try expect_equal(crc32(try data.slice(0, 32)).to_int(), 48494828)
    try expect_equal(crc32(try data.slice(0, 33)).to_int(), 1203717879)

test "IEEE CRC32 preserves larger unaligned views and tails":
    var builder = BytesBuilder()
    for index in 0..16400:
        builder.append(((index * 73 + index / 7) % 256).to_uint8().get(0))

    let data = builder.build()

    for length in [16381, 16382, 16383, 16384, 16385, 16386, 16387, 16388, 16389]:
        for offset in 0..4:
            let view = try data.slice(offset, offset + length)
            try expect_equal(crc32(view), reference(view))
