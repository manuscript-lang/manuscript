import base64_encode, base64_decode from "@std/encoding.ms"
import Bytes, BytesBuilder from "@std/bytes.ms"
import expect_equal from "@std/test.ms"

test "empty Base64 accepts default and explicit alphabets":
    let empty = Bytes([])
    try expect_equal(base64_encode(empty), "")
    try expect_equal(base64_encode(empty, false), "")
    try expect_equal(base64_encode(empty, true), "")

    let view = try Bytes([251, 255, 0]).slice(1, 1)
    try expect_equal(base64_encode(view), "")
    try expect_equal(base64_encode(view, true), "")

test "Base64 after empty retains alphabets and padding tails":
    try expect_equal(base64_encode(Bytes([])), "")
    try expect_equal(base64_encode(Bytes([251])), "+w==")
    try expect_equal(base64_encode(Bytes([251, 255])), "+/8=")
    try expect_equal(base64_encode(Bytes([251, 255, 0])), "+/8A")
    try expect_equal(base64_encode(Bytes([251]), true), "-w==")
    try expect_equal(base64_encode(Bytes([251, 255]), true), "-_8=")
    try expect_equal(base64_encode(Bytes([251, 255, 0]), true), "-_8A")

test "Base64 encodes every byte and empty views":
    var out = BytesBuilder()
    for n in 0..256:
        out.append(n.to_uint8().get(0))

    let data = out.build()
    try expect_equal(
        base64_encode(data),
        "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8gISIjJCUmJygpKissLS4vMDEyMzQ1Njc4OTo7PD0+P0BBQkNERUZHSElKS0xNTk9QUVJTVFVWV1hZWltcXV5fYGFiY2RlZmdoaWprbG1ub3BxcnN0dXZ3eHl6e3x9fn+AgYKDhIWGh4iJiouMjY6PkJGSk5SVlpeYmZqbnJ2en6ChoqOkpaanqKmqq6ytrq+wsbKztLW2t7i5uru8vb6/wMHCw8TFxsfIycrLzM3Oz9DR0tPU1dbX2Nna29zd3t/g4eLj5OXm5+jp6uvs7e7v8PHy8/T19vf4+fr7/P3+/w=="
    )
    try expect_equal(
        base64_encode(data, true),
        "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8gISIjJCUmJygpKissLS4vMDEyMzQ1Njc4OTo7PD0-P0BBQkNERUZHSElKS0xNTk9QUVJTVFVWV1hZWltcXV5fYGFiY2RlZmdoaWprbG1ub3BxcnN0dXZ3eHl6e3x9fn-AgYKDhIWGh4iJiouMjY6PkJGSk5SVlpeYmZqbnJ2en6ChoqOkpaanqKmqq6ytrq-wsbKztLW2t7i5uru8vb6_wMHCw8TFxsfIycrLzM3Oz9DR0tPU1dbX2Nna29zd3t_g4eLj5OXm5-jp6uvs7e7v8PHy8_T19vf4-fr7_P3-_w=="
    )

    let empty = try data.slice(127, 127)
    try expect_equal(base64_encode(empty), "")
    try expect_equal(try base64_decode(base64_encode(data)), data)
    try expect_equal(try base64_decode(base64_encode(data, true), true), data)

fn padded_input(length: Int) Bytes:
    var out = BytesBuilder()
    out.append(42)

    for i in 0..length:
        let byte = if i % 3 == 0: 251 else: (if i % 3 == 1: 255 else: 0)

        out.append(byte.to_uint8().get(0))

    out.append(42)
    return out.build().slice(1, length + 1).get(Bytes([]))

test "Base64 batches preserve tails and sliced byte inputs":
    for length in [
        12285, 12286, 12287, 12288, 12289, 12290, 12291, 24573, 24574, 24575, 24576,
        24577, 24578, 24579
    ]:
        let data = padded_input(length)
        try expect_equal(data.length(), length)

        let tail = if length % 3 == 1: "+w==" else: (
            if length % 3 == 2: "+/8=" else: ""
        )

        let url_tail = if length % 3 == 1: "-w==" else: (
            if length % 3 == 2: "-_8=" else: ""
        )

        try expect_equal(base64_encode(data), (try "+/8A".repeat(length / 3)) + tail)
        try expect_equal(
            base64_encode(data, true), (try "-_8A".repeat(length / 3)) + url_tail
        )
