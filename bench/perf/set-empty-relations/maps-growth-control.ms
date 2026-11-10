import arguments from "@std/os/env.ms"
import monotonic from "@std/time.ms"

export fn main() Int:
    args := arguments()
    mode := args[0]
    size := args[1].parse_int().get()
    repeats := args[2].parse_int().get()
    prefix := args[3]
    var int_map = Map[Int, Int]()
    var string_map = Map[String, Int]()
    var keys: List[String] = []

    for i in 0..size * 2:
        keys.append("{prefix}{i}")

        if i < size:
            int_map.add(i, i * 2)
            string_map.add(keys[i].clone(), i * 2)

    start := monotonic()
    var checksum = 0

    for iteration in 0..repeats:
        if mode == "int_insert":
            var fresh = Map[Int, Int]()
            for i in 0..size:
                fresh.add(i, i * 2)
            for i in 0..size * 2:
                checksum += fresh.get_or(i, 0)
        else if mode == "string_insert":
            var fresh = Map[String, Int]()
            for i in 0..size:
                fresh.add(keys[i].clone(), i * 2)
            for i in 0..size * 2:
                checksum += fresh.get_or(keys[i], 0)
        else if mode == "int_churn":
            for i in 0..size:
                if i % 2 == 0:
                    int_map.remove(i)
            for i in 0..size:
                if i % 2 == 0:
                    int_map.add(i, i * 2)
            for i in 0..size * 2:
                checksum += int_map.get_or(i, 0)
        else:
            return 2

    elapsed := monotonic().difference(start).to_nanoseconds()
    print("{elapsed} {checksum}")
    return 0
