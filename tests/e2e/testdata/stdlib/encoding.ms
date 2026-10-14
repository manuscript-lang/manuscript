import {
    base64_encode,
    base64_decode,
    hex_encode,
    hex_decode,
    EncodingError
} from "@std/encoding.ms"
import Bytes from "@std/bytes.ms"
import List from "@std/collections.ms"
import Result from "@std/result.ms"
import panic from "@std/faults.ms"
import value from "./support/results.ms"

test "encoding known vectors and exact output limits":
    let data = Bytes([0, 255, 66])
    if hex_encode(data) != "00ff42": return panic("hex vector")
    if value(hex_decode(text: "00FF42", max_bytes: 3)) != data: return panic(
        "hex decoding"
    )
    if base64_encode(data: data, url_safe: false) != "AP9C": return panic(
        "base64 vector"
    )
    if value(base64_decode(text: "_w==", url_safe: true)) != Bytes([255]): return panic(
        "URL alphabet"
    )
    if value(hex_decode(text: "", max_bytes: 0)) != Bytes([]): return panic(
        "empty zero budget"
    )

test "encoding rejects malformed data and invalid budgets":
    for text in ["Zh==", "Zg=", "Zg==\n", "_w=="]:
        let actual = base64_decode(text: text, url_safe: false)
        let expected: Result[Bytes, EncodingError] = error(EncodingError.InvalidData)
        if actual != expected: return panic("noncanonical base64 accepted")

    let limited: Result[Bytes, EncodingError] = error(EncodingError.LimitExceeded)
    if hex_decode(text: "00ff", max_bytes: 1) != limited: return panic("hex limit")

    let invalid: Result[Bytes, EncodingError] = error(EncodingError.InvalidInput)
    if hex_decode(text: "", max_bytes: -1) != invalid: return panic("negative limit")
