import expect_equal, expect_fault, expect_some from "@std/test/test.ms"
import TextCursor, cursor from "@std/text.ms"

fn read_all(text: String) List[String]:
    var at = cursor(text)
    var out: List[String] = []
    while not at.is_done():
        out.append(at.read().get())
    return out

test "a cursor reads every scalar width in order and matches chars":
    for text in ["", "abc", "héllo wörld", "日本語", "a🙂b🙂", "e\u{301}x"]:
        expect_equal(read_all(text), text.chars()) | try

test "peek does not move and the end reads none":
    var at = cursor("é!")
    expect_equal(at.peek(), "é") | try
    expect_equal(at.peek(), "é") | try
    expect_equal(at.offset(), 0) | try
    expect_equal(at.read(), "é") | try
    expect_equal(at.offset(), 2) | try
    expect_equal(at.read(), "!") | try
    expect_equal(at.is_done(), true) | try
    expect_equal(at.peek(), none) | try
    expect_equal(at.read(), none) | try

test "marks slice and rewind on scalar boundaries":
    var at = cursor("héllo wörld")
    let start = at.offset()
    while not at.is_done():
        if at.read().get() == " ": break
    expect_equal(at.since(start), "héllo ") | try

    let word = at.offset()
    at.read()
    at.read()
    expect_equal(at.since(word), "wö") | try
    at.seek(start)
    expect_equal(at.read(), "h") | try
    expect_equal(at.since(start), "h") | try

fn check_since(at: TextCursor) Unit:
    let _text = at.since(1)

test "a mark inside a scalar or past the end faults":
    var at = cursor("é")
    let _a = expect_fault(fn: at.seek(1)) | try
    let _b = expect_fault(fn: at.seek(3)) | try
    let _c = expect_fault(fn: check_since(at)) | try

test "a long non-ASCII scan is linear":
    let text = "héllo wörld ünï ".repeat(6250).get("")
    var at = cursor(text)
    var found = 0
    while not at.is_done():
        if at.read().get() == "ö": found += 1
    expect_equal(found, 6250) | try
