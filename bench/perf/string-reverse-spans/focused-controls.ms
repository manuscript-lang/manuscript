import stdout from "@std/io.ms"
import clock from "@std/time.ms"

type Pattern:
    name: String
    forward: String
    backward: String

fn iterations_for(size: Int) Int:
    if size <= 32: return 5000000
    if size >= 262144: return 16
    if size >= 4096: return 1024

    return 100000

fn reverse_sum(text: String, expected: String) Int:
    let output = text.reverse()
    if output != expected: return -1

    return output.byte_length() + 17

fn measure(name: String, text: String, expected: String) Int:
    let expected_sum = expected.byte_length() + 17
    if reverse_sum(text, expected) != expected_sum: return 1

    let iterations = iterations_for(text.byte_length())
    var checksum = 0
    let started = clock().now()
    for iteration in 0..iterations:
        checksum += reverse_sum(text, expected)

    let elapsed = clock().now().difference(started).to_nanoseconds()
    if checksum != expected_sum * iterations: return 1

    let _written = stdout().write(
        "{name},{text.byte_length()},{iterations},{elapsed},{checksum}\n"
    )
    return 0

export fn main() Int:
    let _header = stdout().write("case,input_bytes,iterations,elapsed_ns,checksum\n")

    for pattern in [
        Pattern("ascii_mixed", "abcDE09_", "_90EDcba"),
        Pattern("ascii_controls", "a\u{0}b\tc\nd!", "!d\nc\tb\u{0}a")
    ]:
        for length in [0, 1, 2, 7]:
            let copies = length / 8
            let tail = length % 8
            let text = (
                pattern.forward.repeat(copies).get()
                + pattern.forward.slice_scalars(0, tail).get()
            )
            let expected = (
                pattern.backward.slice_scalars(8 - tail, 8).get()
                + pattern.backward.repeat(copies).get()
            )
            if measure("{pattern.name}_n{length}", text, expected) != 0: return 1

    for pattern in [
        Pattern("two_byte", "éΩüß", "ßüΩé"),
        Pattern("replacement", "\u{fffd}", "\u{fffd}")
    ]:
        for copies in [1]:
            let text = pattern.forward.repeat(copies).get()
            let expected = pattern.backward.repeat(copies).get()
            if measure("{pattern.name}_copies{copies}", text, expected) != 0: return 1

    return 0
