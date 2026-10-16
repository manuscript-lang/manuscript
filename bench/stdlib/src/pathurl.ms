import {bench} from "./harness.ms"
import {basename, join, normalize} from "@std/path.ms"
import {parse, encode_component} from "@std/url.ms"
import {sqrt, sin} from "@std/math.ms"

export fn bench_path_url_math() -> Unit:
    bench(
        "path.join_normalize",
        50000,
        fn() -> Int:
            var n = 0
            var i = 0

            while i < 50000:
                n = (
                    n
                    + normalize(
                        path: join(
                            parts: ["/a", "b/../c", "d.txt"]
                        )
                    ).length()
                )
                i = i + 1

            return n
    )
    bench(
        "path.basename",
        100000,
        fn() -> Int:
            var n = 0
            var i = 0

            while i < 100000:
                n = n + basename(path: "/a/b/c/file.txt").length()
                i = i + 1

            return n
    )
    bench(
        "url.parse",
        20000,
        fn() -> Int:
            var n = 0
            var i = 0

            while i < 20000:
                match parse(text: "https://example.com:8080/a/b?x=1&y=2#frag"):
                    ok(_): n = n + 1
                    error(_): unit

                i = i + 1

            return n
    )
    bench(
        "url.encode_component",
        50000,
        fn() -> Int:
            var n = 0
            var i = 0

            while i < 50000:
                n = n + encode_component(text: "a b&c=d/é").length()
                i = i + 1

            return n
    )
    bench(
        "math.sqrt_sin",
        1000000,
        fn() -> Int:
            var acc = 0.0
            var i = 0

            while i < 1000000:
                acc = acc + sqrt(value: 2.0) + sin(value: 1.0)
                i = i + 1

            return acc.truncate_to_int().unwrap_or(0)
    )
