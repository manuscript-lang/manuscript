# conform: tags=control-flow,formatter,interfaces,interpolation,modules,parser,records,stdlib-cleanup,stdlib-io,strings,tier-stdlib,with-cleanup
# conform: phase=parse
# conform: origin=tests/e2e/testdata/projects/signal/main.ms
from "@std/io.ms" import stdout
from "@std/io.ms" import WriteStream
from "@std/core.ms" import Closeable

type Resource:
    label: String
    output: WriteStream

impl Closeable for Resource:
    def close() -> Unit:
        let _ignored = self.output.write(f"close {self.label}\n")

export def main() -> Int:
    let output = stdout()

    with let resource = Resource("parent", output):
        with let child = Resource("child", output):
            let _ignored = output.write("ready\n")
            while True:
                continue

    return 0
