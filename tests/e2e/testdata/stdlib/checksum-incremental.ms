import adler32, crc32, Adler32, Crc32 from "@std/data/checksum.ms"
import Bytes, BytesBuilder from "@std/bytes.ms"
import CompressionFormat from "@std/io/archive.ms"
import expect_equal from "@std/test/test.ms"

test "Adler32 RFC vectors and zlib trailer agree":
    try expect_equal(adler32(Bytes([])).to_int(), 1)
    try expect_equal(adler32("Wikipedia".to_bytes()).to_int(), 300286872)
    try expect_equal(adler32("123456789".to_bytes()).to_int(), 152961502)

    var binary = BytesBuilder()
    for byte in 0..256:
        binary.append(byte.to_uint8().get(0))
    try expect_equal(adler32(binary.build()).to_int(), 2918612865)

    let input = "a checksum without compressing the input".to_bytes()
    let encoded = try CompressionFormat.Zlib.compress(input)
    try expect_equal(adler32(input), try encoded.uint32_be(encoded.length() - 4))

test "checksum values start empty and observations do not reset":
    var crc = Crc32()
    var adler = Adler32()
    let empty = Bytes([])
    try expect_equal(crc.value().to_int(), 0)
    try expect_equal(adler.value().to_int(), 1)
    crc.update(empty)
    adler.update(empty)
    try expect_equal(crc.value().to_int(), 0)
    try expect_equal(adler.value().to_int(), 1)

    var custom = Adler32(state: 4294967295)
    custom.update(empty)
    try expect_equal(custom.value().to_int(), 4294967295)
    crc.update("1234".to_bytes())
    adler.update("Wiki".to_bytes())

    let crc_prefix = crc.value()
    let adler_prefix = adler.value()
    try expect_equal(crc.value(), crc_prefix)
    try expect_equal(adler.value(), adler_prefix)
    crc.update(empty)
    adler.update(empty)
    try expect_equal(crc.value(), crc_prefix)
    try expect_equal(adler.value(), adler_prefix)
    crc.update("56789".to_bytes())
    adler.update("pedia".to_bytes())
    try expect_equal(crc.value().to_int(), 3421780262)
    try expect_equal(adler.value().to_int(), 300286872)
    try expect_equal(crc_prefix, crc32("1234".to_bytes()))
    try expect_equal(adler_prefix, adler32("Wiki".to_bytes()))

test "checksum clones advance independently from the same prefix":
    let prefix = "abc".to_bytes()
    var crc = Crc32()
    var adler = Adler32()
    crc.update(prefix)
    adler.update(prefix)

    var crc_branch = crc.clone()
    var adler_branch = adler.clone()
    crc.update("def".to_bytes())
    adler.update("def".to_bytes())
    crc_branch.update("xyz".to_bytes())
    adler_branch.update("xyz".to_bytes())
    try expect_equal(crc.value(), crc32("abcdef".to_bytes()))
    try expect_equal(adler.value(), adler32("abcdef".to_bytes()))
    try expect_equal(crc_branch.value(), crc32("abcxyz".to_bytes()))
    try expect_equal(adler_branch.value(), adler32("abcxyz".to_bytes()))

test "whole and incremental checksums agree across binary chunk boundaries":
    var builder = BytesBuilder()
    for index in 0..4097:
        builder.append(((index * 73 + index / 7) % 256).to_uint8().get(0))

    let data = builder.build()

    for length in [0, 1, 7, 16, 31, 32, 255, 256, 257, 4095, 4096, 4097]:
        let input = try data.slice(0, length)

        for chunk_size in [1, 2, 3, 7, 16, 64, 255, 1024, 4096]:
            var crc = Crc32()
            var adler = Adler32()
            var start = 0

            while start < length:
                let end = if length - start < chunk_size: length else: start + chunk_size
                let chunk = try input.slice(start, end)
                crc.update(chunk)
                adler.update(chunk)
                start = end

            try expect_equal(crc.value(), crc32(input))
            try expect_equal(adler.value(), adler32(input))

    try expect_equal(data.get(17).to_int(), (17 * 73 + 17 / 7) % 256)
