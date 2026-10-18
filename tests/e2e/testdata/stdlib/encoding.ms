import {base64_encode, base64_decode, hex_encode, hex_decode, EncodingError} from "@std/encoding.ms"
import Bytes from "@std/bytes.ms"
import panic from "@std/faults.ms"

test "encoding known vectors and exact output limits":
    let data = Bytes([0, 255, 66])
    if hex_encode(data) != "00ff42": return panic("hex vector")
    if (try hex_decode("00FF42", 3)) != data: return panic("hex decoding")
    if base64_encode(data, url_safe: false) != "AP9C": return panic("base64 vector")
    if (try base64_decode("_w==", url_safe: true)) != Bytes([255]): return panic(
        "URL alphabet"
    )
    if (try hex_decode("", 0)) != Bytes([]): return panic("empty zero budget")

test "encoding rejects malformed data and invalid budgets":
    for text in ["Zh==", "Zg=", "Zg==\n", "_w=="]:
        let actual = base64_decode(text, url_safe: false)
        let expected: Result[Bytes, EncodingError] = error(EncodingError.InvalidData)
        if actual != expected: return panic("noncanonical base64 accepted")

    let limited: Result[Bytes, EncodingError] = error(EncodingError.LimitExceeded)
    if hex_decode("00ff", 1) != limited: return panic("hex limit")

    let invalid: Result[Bytes, EncodingError] = error(EncodingError.InvalidInput)
    if hex_decode("", -1) != invalid: return panic("negative limit")
