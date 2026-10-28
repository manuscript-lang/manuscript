# conform: tags=control-flow,formatter,interfaces,interpolation,modules,parser,records,stdlib-cleanup,stdlib-io,strings,tier-stdlib,with-cleanup
# conform: phase=parse
# conform: origin=tests/e2e/testdata/projects/signal/main.ms
import stdout from "@std/io.ms"
import WriteStream from "@std/io.ms"
import Closeable from "@std/core.ms"

type Resource:
    label: String
    output: WriteStream

impl Closeable for Resource:
    fn close() Unit:
        let _ignored = self.output.write("close {self.label}\n")

export fn main() Int:
    let output = stdout()

    with let resource = Resource("parent", output):
        with let child = Resource("child", output):
            let _ignored = output.write("ready\n")
            while true:
                continue

    return 0
