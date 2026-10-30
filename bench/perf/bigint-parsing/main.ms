import arguments from "@std/process.ms"
import clock from "@std/time.ms"
import stdout from "@std/io.ms"
import parse, BigInt from "@std/math.ms"

export fn main() Int:
    let args = arguments()
    let operation = args[0]
    let radix = args[1].parse_int().get()
    let count = args[2].parse_int().get()
    let expected_checksum = args[3].parse_int().get()
    let inputs = [args[4].clone(), args[5].clone(), args[6].clone(), args[7].clone()]
    let references = inputs.map(
        fn(text: String) BigInt: return parse(text, radix).get()
    )
    for index in 0..4:
        if references.get(index).to_string_radix(radix) != args[8 + index]:
            return 3

    let timer = clock()
    var checksum = 0
    let start = timer.now()

    for i in 0..count:
        let index = i % 4
        let value = parse(inputs.get(index), radix).get()
        if value.compare(references.get(index)) != 0:
            return 1

        checksum += value.sign() * (index + 1)

    let elapsed = timer.now().difference(start).to_nanoseconds()
    let last = references.get((count - 1) % 4).to_string_radix(radix)
    (
        stdout()
        .write(
            "operation={operation} radix={radix} count={count} ns={elapsed} checksum={checksum} last={last}\n"
        )
        .get()
    )
    if checksum != expected_checksum:
        return 1

    return 0
