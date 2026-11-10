import Bytes from "@std/bytes.ms"
import stdout from "@std/io/io.ms"
import arguments from "@std/os/env.ms"

extern type Counter

enum ParseError:
    Failed(code: Int, message: String)
    Empty
    Unknown(code: Int)

fn text(cause: ParseError) String:
    match cause:
        Failed(code, message): return "failed at {code}: {message}"
        Empty: return "empty"
        Unknown(code): return "unknown {code}"

extern fn abi_i8(x: Int8) Int8

extern fn abi_i16(x: Int16) Int16

extern fn abi_i32(x: Int32) Int32

extern fn abi_u8(x: UInt8) UInt8

extern fn abi_u16(x: UInt16) UInt16

extern fn abi_u32(x: UInt32) UInt32

extern fn abi_u64(x: UInt64) UInt64

extern fn abi_f32(x: Float32) Float32

extern fn abi_not(x: Bool) Bool

extern fn abi_mixed(
    a: Int8,
    b: UInt8,
    c: Int16,
    d: UInt16,
    e: Int32,
    f: UInt32,
    g: Float32
) Int

extern fn abi_reverse(data: Bytes) Bytes

extern fn abi_cstring_length(text: String) Int

extern fn abi_string_length(text: String) Int

extern fn abi_double(values: List[Int32]) List[Int32]

extern fn abi_sum(values: List[UInt8]) UInt64

extern fn abi_shout(words: List[String]) List[String]

extern fn abi_overflow() List[UInt8]

extern fn abi_counter(start: Int) Counter

extern fn abi_counter_bump(counter: Counter) Int

extern fn abi_drops() Int

extern fn abi_total(counters: List[Counter]) Int

extern fn abi_null() Counter

extern fn abi_parse(text: String) Counter!ParseError

extern fn abi_noisy() String!ParseError

extern fn abi_lazy() String!ParseError

extern fn abi_bad_status() Unit!ParseError

extern fn abi_fault() Unit

extern fn abi_twice(f: fn(Int) Int, x: Int) Int

extern fn abi_describe(f: fn(String, Int8, Bool, Float32, Bytes) String) String

extern fn abi_keep(f: fn(Counter) Unit) Unit

extern fn abi_fire(counter: Counter) Unit

extern fn abi_forget() Unit

extern fn abi_call_wrong(f: fn(Int) Unit) Unit

extern fn abi_call_plain(f: fn() Unit) Unit

extern fn abi_arm_stop() Unit

extern fn abi_wait_for_stop() Int

fn describe(result: Counter!ParseError) String:
    if counter := result:
        return "ok {abi_counter_bump(counter)}"

    return "error {text(result.err())}"

fn callbacks() Unit:
    var out = stdout()
    step := 5
    _ := out.write("{abi_twice(fn(x: Int) Int: x * 2 + step, 1)}\n")
    _ := out.write(
        abi_describe(
            fn(s: String, i: Int8, b: Bool, f: Float32, data: Bytes) String: "{s} {i} {b} {f} {data.length()}"
        )
        + "\n"
    )
    label := "fired"
    abi_keep(
        fn(c: Counter) Unit:
            _ := stdout().write("{label} {abi_counter_bump(c)}\n")
    )

    c := abi_counter(40)
    abi_fire(c)
    abi_fire(c)
    abi_forget()

fn counters() Unit:
    a := abi_counter(1)
    b := a
    _ := abi_counter_bump(b)
    list := [a, abi_counter(10)]
    _ := stdout().write("total {abi_total(list)}\n")

export fn main() Int:
    var out = stdout()
    mode := arguments().get(index: 0, default: "")

    if mode == "string-length":
        for text in ["", "x", "123456789012345", "1234567890123456", "é🙂\u{0}é"]:
            if abi_string_length(text) != text.byte_length(): return 1

        owned := "ab".repeat(20).get()
        if abi_string_length(owned) != 40: return 2
        if abi_string_length(owned.clone()) != 40: return 3
        if abi_string_length(owned.view(1, 39)) != 38: return 4
        if abi_string_length(owned + "\u{0}") != 41: return 5

        unicode := "é🙂".repeat(20).get()
        if abi_string_length(unicode) != 120: return 6

        return 0

    if mode == "overflow":
        _ := abi_overflow()
        return 0

    if mode == "null":
        _ := abi_null()
        return 0

    if mode == "status":
        _ := abi_bad_status()
        return 0

    if mode == "fault":
        abi_fault()
        return 0

    if mode == "callkind":
        abi_call_wrong(fn(x: Int) Unit: return)
        return 0

    if mode == "callfault":
        abi_call_plain(fn() Unit: abi_fault())
        return 0

    if mode == "stop":
        abi_arm_stop()

        _ := out.write("hooks {abi_wait_for_stop()}\n")
        return 0

    _ := out.write(
        "{abi_i8(-128)} {abi_i16(-32768)} {abi_i32(-2147483648)} {abi_u8(255)} {abi_u16(65535)} {abi_u32(4294967295)} {abi_u64(18446744073709551615)}\n"
    )
    _ := out.write(
        "{abi_f32(3.0)} {abi_not(true)} {abi_mixed(-1, 255, -1, 65535, -1, 4294967295, 2.5)}\n"
    )
    reversed := abi_reverse("abc".to_bytes())
    _ := out.write(
        "{reversed.decode_utf8().get("")} {abi_cstring_length("hello")} {abi_cstring_length("a\u{0}b")}\n"
    )
    _ := out.write(
        "{abi_double([1, -2, 1000000000])} {abi_sum([200, 100, 255])} {abi_shout(["hi", "there"])}\n"
    )
    counters()

    _ := out.write("drops {abi_drops()}\n")
    _ := out.write(
        "{describe(abi_parse("42"))} {describe(abi_parse("4x"))} {describe(abi_parse(""))} {describe(abi_parse("?"))}\n"
    )
    _ := out.write("drops {abi_drops()}\n")
    _ := out.write("{abi_noisy().get("")} [{abi_lazy().get("x")}]\n")
    callbacks()

    _ := out.write("drops {abi_drops()}\n")
    return 0
