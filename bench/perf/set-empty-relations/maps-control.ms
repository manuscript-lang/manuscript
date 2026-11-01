import arguments from "@std/os/process.ms"
import monotonic from "@std/os/time.ms"
import stdout from "@std/io/io.ms"

export fn main() Int:
    let args = arguments()
    let mode = args[0]
    let size = args[1].parse_int().get()
    let repeats = args[2].parse_int().get()
    let prefix = args[3]
    var int_map = Map[Int, Int]()
    var string_map = Map[String, Int]()
    var keys: List[String] = []

    for i in 0..size * 2:
        keys.append("{prefix}{i}")

        if i < size:
            int_map.add(i, i * 2)
            string_map.add(keys[i].clone(), i * 2)

    let start = monotonic()
    var checksum = 0

    for iteration in 0..repeats:
        if mode == "int_get":
            for i in 0..size * 2:
                checksum += int_map.get_or(i, 0)
        else if mode == "string_get":
            for i in 0..size * 2:
                checksum += string_map.get_or(keys[i], 0)
        else if mode == "int_update":
            for i in 0..size:
                int_map.add(i, i * 2)
            for i in 0..size * 2:
                checksum += int_map.get_or(i, 0)
        else:
            for i in 0..size:
                string_map.add(keys[i].clone(), i * 2)
            for i in 0..size * 2:
                checksum += string_map.get_or(keys[i], 0)

    let elapsed = monotonic().difference(start).to_nanoseconds()
    stdout().write("{elapsed} {checksum}\n").get()
    return 0
