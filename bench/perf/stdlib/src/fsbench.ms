from "@std/collections.ms" import range
from "./harness.ms" import bench
from "@std/fs.ms" import filesystem, FileSystem
from "@std/log.ms" import create, file_transport, Transport, Logger

def run(fs: FileSystem, root: String) -> Unit:
    let data = "0123456789abcdef".repeat(4096).get("").to_bytes()

    bench(
        "fs.write_file_64k",
        200,
        lambda () -> Int:
            var n = 0
            for i in range(0, 200):
                if fs.write_file_bytes(f"{root}/f{i}.bin", data, replace: True).is_ok():
                    n += 1
            return n
    )

    bench(
        "fs.read_file_64k",
        200,
        lambda () -> Int:
            var n = 0
            for i in range(0, 200):
                if let b = fs.read_file(f"{root}/f{i}.bin"):
                    n += b.length()
            return n
    )

    bench(
        "fs.stat",
        200,
        lambda () -> Int:
            var n = 0
            for i in range(0, 200):
                if fs.stat(f"{root}/f{i}.bin", follow_links: True).is_ok():
                    n += 1
            return n
    )

    bench(
        "fs.list_200",
        1,
        lambda () -> Int:
            if let entries = fs.list(root):
                return entries.length()

            return 0
    )

def log_run(path: String) -> Unit:
    if let transport = file_transport(path):
        log_with(transport)

def log_with(transport: Transport) -> Unit:
    if let logger = create(transport, timestamp: False):
        log_many(logger)

def log_many(logger: Logger) -> Unit:
    bench(
        "log.info",
        20000,
        lambda () -> Int:
            var n = 0
            for i in range(0, 20000):
                if logger.info(f"request {i} handled").is_ok():
                    n += 1
            return n
    )

export def bench_fs() -> Unit:
    let fs = filesystem()

    if let dir = fs.temporary("ms-bench-"):
        run(fs, dir.path())
        log_run(f"{dir.path()}/log.txt")
        dir.close()
