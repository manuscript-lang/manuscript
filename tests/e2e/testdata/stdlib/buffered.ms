import (
    buffered_reader,
    buffered_writer,
    scan,
    ScanMode,
    ScanStep
) from "@std/io/buffered.ms"
import from_bytes from "@std/io/streams.ms"
import read_all, IoError, ReadStream from "@std/io/io.ms"
import Bytes from "@std/bytes.ms"
import panic from "@std/core.ms"
import open, read_file, temporary from "@std/os/fs.ms"
import expect_ok from "@std/test/test.ms"

test "reader peeks without consuming":
    var reader = buffered_reader(from_bytes("hello world".to_bytes(), 3), 2)
    if (try reader.peek(5)) != "hello".to_bytes(): return panic("peek")
    if (try reader.peek(5)) != "hello".to_bytes(): return panic("peek again")
    if (try reader.read_exact(6)) != "hello ".to_bytes(): return panic("read_exact")
    if (try reader.peek(100)) != "world".to_bytes(): return panic("peek past end")
    if (try reader.read_exact(5)) != "world".to_bytes(): return panic("rest")

    let short = reader.read_exact(1)
    if short.is_ok(): return panic("read_exact at end")

test "read_until splits on a delimiter":
    var reader = buffered_reader(from_bytes("a,bb,,ccc".to_bytes(), 2), 3)
    let comma: UInt8 = 44
    let parts = [
        (try reader.read_until(comma)).get(), (try reader.read_until(comma)).get(),
        (try reader.read_until(comma)).get(), (try reader.read_until(comma)).get()
    ]
    if parts != ["a".to_bytes(), "bb".to_bytes(), "".to_bytes(), "ccc".to_bytes()]: return panic(
        "parts"
    )
    if (try reader.read_until(comma)).is_some(): return panic("end")

test "read_until enforces its limit":
    var reader = buffered_reader(from_bytes("abcdefgh,x".to_bytes(), 2), 2)
    let comma: UInt8 = 44
    let result = reader.read_until(comma, 4)
    if not result.is_error(): return panic("limit")
    if result.err() != IoError.LimitExceeded: return panic("limit kind")

test "read_rune decodes whole scalars across chunks":
    var reader = buffered_reader(from_bytes("a\u{e9}\u{1f600}z".to_bytes(), 1), 1)
    var seen = List[String]()

    while true:
        let rune = try reader.read_rune()
        if rune.is_none(): break

        seen.append(rune.get().clone())

    if seen != ["a", "\u{e9}", "\u{1f600}", "z"]: return panic("runes")

test "buffered reader is a stream":
    var reader = buffered_reader(from_bytes("0123456789".to_bytes(), 4), 4)
    if (try reader.peek(2)) != "01".to_bytes(): return panic("peek")
    if (try reader.read(3)).get() != "012".to_bytes(): return panic("limited read")
    if (try read_all(reader)) != "3456789".to_bytes(): return panic("rest")

test "writer batches small writes":
    let dir = temporary("manuscript-buffered-") | try expect_ok
    let path = "{dir.path()}/out.bin"
    var file = open(path: path, flags: "w", mode: 420) | try expect_ok
    var writer = buffered_writer(file.writer(), 8)
    try writer.write("abc")
    try writer.write("def")
    if writer.held != 6: return panic("held")

    try writer.write("ghi")
    if writer.held != 3: return panic("drained before overflow")

    try writer.write("0123456789")
    if writer.held != 0: return panic("large write goes through")

    try writer.write("z")
    if writer.held != 1: return panic("tail held")

    try writer.flush()
    if (read_file(path: path) | try expect_ok) != "abcdefghi0123456789z".to_bytes(): return panic(
        "content"
    )

fn collect(input: ReadStream, split: ScanMode = ScanMode.Lines) List[String]:
    var scanner = scan(input, split)
    var out = List[String]()
    for token in scanner:
        out.append(token.clone())
    return out

test "scanner lines handles CRLF and an unterminated tail":
    let found = collect(from_bytes("one\r\ntwo\n\nlast".to_bytes(), 3))
    if found != ["one", "two", "", "last"]: return panic("lines")

test "scanner words and runes":
    let words = collect(
        from_bytes("  the quick\t brown\nfox ".to_bytes(), 2), ScanMode.Words
    )
    if words != ["the", "quick", "brown", "fox"]: return panic("words")

    let runes = collect(from_bytes("a\u{e9}z".to_bytes(), 1), ScanMode.Runes)
    if runes != ["a", "\u{e9}", "z"]: return panic("runes")

test "scanner delimiter and custom split":
    let parts = collect(from_bytes("a--b----c".to_bytes(), 2), ScanMode.Delimiter("--"))
    if parts != ["a", "b", "", "c"]: return panic("delimiter")

    # Tokens are runs of three bytes.
    let threes = ScanMode.Custom(
        fn(window: Bytes, at_eof: Bool) ScanStep:
            if window.length() >= 3: return ScanStep(3, (window.slice(0, 3)).get())
            if at_eof and window.length() > 0: return ScanStep(window.length(), window)

            return ScanStep(0)
    )

    let chunks = collect(from_bytes("abcdefgh".to_bytes(), 2), threes)
    if chunks != ["abc", "def", "gh"]: return panic("custom")

test "scanner reports limits and bad data":
    var long = scan(from_bytes("abcdefghij\nx".to_bytes(), 3), ScanMode.Lines, 4)
    for token in long:
        return panic("token over the limit")
    if long.error() != IoError.LimitExceeded: return panic("limit error")

    var bad = scan(from_bytes(Bytes([255, 10]), 2))
    for token in bad:
        return panic("invalid utf8 token")
    if bad.error() != IoError.InvalidData: return panic("data error")

    var empty = scan(from_bytes("x".to_bytes()), ScanMode.Delimiter(""))
    for token in empty:
        return panic("empty delimiter")
    if empty.error() != IoError.InvalidInput: return panic("delimiter error")
