from "@std/io.ms" import stdout
from "@std/io.ms" import WriteStream
from "@std/core.ms" import Closeable

type Resource:
    label: String
    output: WriteStream

impl Closeable for Resource:
    var def close() -> Unit:
        let _ignored = self.output.write(f"close {self.label}\n")

export def main() -> Int:
    var output = stdout()

    with Resource("parent", stdout()) as resource:
        with Resource("child", stdout()) as child:
            let _ignored = output.write("ready\n")
            while True:
                continue

    return 0
