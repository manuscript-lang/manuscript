import bench from "./harness.ms"
import FileSystem, list, read_file, stat, temporary from "@std/os/fs.ms"
import create, file_transport, Transport, Logger from "@std/log.ms"

fn run(fs: FileSystem, root: String) Unit:
    let data = "0123456789abcdef".repeat(4096).get("").to_bytes()

    bench(
        "fs.write_file_64k",
        200,
        fn() Int:
            var n = 0
            for i in 0..200:
                if (
                    fs
                    .write_file_bytes(
                        "{root}/f{i}.bin", data, replace: true
                    )
                    .is_ok()
                ):
                    n += 1
            return n
    )

    bench(
        "fs.read_file_64k",
        200,
        fn() Int:
            var n = 0
            for i in 0..200:
                if let b = read_file("{root}/f{i}.bin"):
                    n += b.length()
            return n
    )

    bench(
        "fs.stat",
        200,
        fn() Int:
            var n = 0
            for i in 0..200:
                if stat("{root}/f{i}.bin", follow_links: true).is_ok():
                    n += 1
            return n
    )

    bench(
        "fs.list_200",
        1,
        fn() Int:
            if let entries = list(root):
                return entries.length()

            return 0
    )

fn log_run(path: String) Unit:
    if let transport = file_transport(path):
        log_with(transport)

fn log_with(transport: Transport) Unit:
    if let logger = create(transport, timestamp: false):
        log_many(logger)

fn log_many(logger: Logger) Unit:
    bench(
        "log.info",
        20000,
        fn() Int:
            var n = 0
            for i in 0..20000:
                if logger.info("request {i} handled").is_ok():
                    n += 1
            return n
    )

export fn bench_fs() Unit:
    if var dir = temporary("ms-bench-"):
        run(fs, dir.path())
        log_run("{dir.path()}/log.txt")
        dir.close().get(none)
