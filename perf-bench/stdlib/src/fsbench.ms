import range from "@std/collections.ms"
import {bench} from "./harness.ms"
import {filesystem, FileSystem} from "@std/fs.ms"
import {create, file_transport, Transport, Logger} from "@std/log.ms"

fn run(fs: FileSystem, root: String) -> Unit:
    let data = "0123456789abcdef".repeat(count: 4096).unwrap_or("").to_bytes()
    bench(
        "fs.write_file_64k",
        200,
        fn() -> Int:
            var n = 0

            for i in range(0, 200):
                match fs.write_file(path: "{root}/f{i}.bin", data: data, replace: true):
                ok(_): n = n + 1
                error(_): unit

            return n
    )
    bench(
        "fs.read_file_64k",
        200,
        fn() -> Int:
            var n = 0

            for i in range(0, 200):
                match fs.read_file(path: "{root}/f{i}.bin"):
                ok(b): n = n + b.length()
                error(_): unit

            return n
    )
    bench(
        "fs.stat",
        200,
        fn() -> Int:
            var n = 0

            for i in range(0, 200):
                match fs.stat(path: "{root}/f{i}.bin", follow_links: true):
                ok(_): n = n + 1
                error(_): unit

            return n
    )
    bench(
        "fs.list_200",
        1,
        fn() -> Int:
            match fs.list(path: root):
            ok(entries): return entries.length()
            error(_): return 0
    )

fn log_run(path: String) -> Unit:
    match file_transport(path: path):
    ok(transport): log_with(transport)
    error(_): unit

fn log_with(transport: Transport) -> Unit:
    match create(transport: transport, timestamp: false):
    ok(logger): log_many(logger)
    error(_): unit

fn log_many(logger: Logger) -> Unit:
    bench(
        "log.info",
        20000,
        fn() -> Int:
            var n = 0

            for i in range(0, 20000):
                match logger.info("request {i} handled"):
                ok(_): n = n + 1
                error(_): unit

            return n
    )

export fn bench_fs() -> Unit:
    let fs = filesystem()

    match fs.temporary("ms-bench-"):
    ok(dir):
        run(fs, dir.path())
        log_run("{dir.path()}/log.txt")
        dir.close()
    error(_): unit
