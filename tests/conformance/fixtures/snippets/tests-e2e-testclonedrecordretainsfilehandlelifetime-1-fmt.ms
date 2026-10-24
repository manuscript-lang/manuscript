# conform: tags=aliasing,control-flow,faults,formatter,match,modules,optional,parser,records,stdlib-io,strings,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/mutation_test.go:49 TestClonedRecordRetainsFileHandleLifetime
from "@std/io.ms" import files
from "@std/io.ms" import File
from "@std/io.ms" import IoError

type Holder:
    file: File
    label: String

export def main() -> Int:
    let opened = files().open("data.txt")
    if opened.is_error():
        return 4

    let file = opened.get()
    let read = file.read(1)
    if read.is_error():
        return 7

    let chunk = read.get()

    match chunk:
        case some(data):
            if data.decode_utf8() != some(value: "d"):
                return 5
        case none:
            return 6

    let original = Holder(file: file, label: "original")
    var copy = original.clone()
    copy.label = "copy"
    if original.label != "original":
        return 1

    copy.file.close()

    let reread = original.file.read(1)
    if reread.is_ok():
        return 3

    let cause = reread.err()

    match cause:
        case IoError.Closed:
            return 0
        case _:
            return 2
