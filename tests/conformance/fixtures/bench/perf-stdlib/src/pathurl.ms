import bench from "./harness.ms"
import basename, join, normalize from "@std/fs.ms"
import parse, encode_component from "@std/net.ms"
import sqrt, sin from "@std/math.ms"

export fn bench_path_url_math() Unit:
    bench(
        "path.join_normalize",
        50000,
        fn() Int:
            var n = 0
            for i in 0..50000:
                n += join(["/a", "b/../c", "d.txt"]) | normalize | .length()
            return n
    )

    bench(
        "path.basename",
        100000,
        fn() Int:
            var n = 0
            for i in 0..100000:
                n += basename("/a/b/c/file.txt").length()
            return n
    )

    bench(
        "url.parse",
        20000,
        fn() Int:
            let address = "https://example.com:8080/a/b?x=1&y=2#frag"
            var n = 0
            for i in 0..20000:
                if parse(address).is_ok(): n += 1
            return n
    )

    bench(
        "url.encode_component",
        50000,
        fn() Int:
            var n = 0
            for i in 0..50000:
                n += encode_component("a b&c=d/é").length()
            return n
    )

    bench(
        "math.sqrt_sin",
        1000000,
        fn() Int:
            var acc = 0.0
            for i in 0..1000000:
                acc += sqrt(2.0) + sin(1.0)
            return acc.truncate_to_int().get(0)
    )
