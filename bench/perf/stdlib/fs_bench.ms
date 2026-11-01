import keep, measure from "@std/test/bench.ms"
import Bytes from "@std/bytes.ms"
import FileSystem, list, read_file, stat, temporary, write_file_bytes from "@std/os/fs.ms"
import create, file_transport from "@std/log.ms"

fn block() Bytes:
    return "0123456789abcdef".repeat(4096).get("").to_bytes()

# Writes the 200 files that the read, stat, and list cases use.
fn populate(fs: FileSystem, root: String) Unit:
    let data = block()
    for i in 0..200:
        let _written = write_file_bytes("{root}/f{i}.bin", data, replace: true)

bench "fs.write_file_64k":
    let data = block()

    if var dir = temporary("ms-bench-"):
        let root = dir.path()

        fn work() Result[Unit, Error]:
            var n = 0
            for i in 0..200:
                if write_file_bytes("{root}/f{i}.bin", data, replace: true).is_ok():
                    n += 1
            return keep(n)

        try measure(200, work)
        dir.close().get(none)

bench "fs.read_file_64k":
    if var dir = temporary("ms-bench-"):
        let root = dir.path()
        populate(fs, root)

        fn work() Result[Unit, Error]:
            var n = 0
            for i in 0..200:
                if let b = read_file("{root}/f{i}.bin"):
                    n += b.length()
            return keep(n)

        try measure(200, work)
        dir.close().get(none)

bench "fs.stat":
    if var dir = temporary("ms-bench-"):
        let root = dir.path()
        populate(fs, root)

        fn work() Result[Unit, Error]:
            var n = 0
            for i in 0..200:
                if stat("{root}/f{i}.bin", follow_links: true).is_ok():
                    n += 1
            return keep(n)

        try measure(200, work)
        dir.close().get(none)

bench "fs.list_200":
    if var dir = temporary("ms-bench-"):
        let root = dir.path()
        populate(fs, root)

        fn work() Result[Unit, Error]:
            if let entries = list(root):
                return keep(entries.length())

            return keep(0)

        try measure(1, work)
        dir.close().get(none)

bench "log.info":
    if var dir = temporary("ms-bench-"):
        if let transport = file_transport("{dir.path()}/log.txt"):
            if let logger = create(transport, timestamp: false):
                fn work() Result[Unit, Error]:
                    var n = 0
                    for i in 0..20000:
                        if logger.info("request {i} handled").is_ok():
                            n += 1
                    return keep(n)

                try measure(20000, work)

        dir.close().get(none)
