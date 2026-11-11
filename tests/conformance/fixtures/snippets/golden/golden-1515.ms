// conform: tags=diagnostics
// conform: phase=check
import files from "@std/io/io.ms"
import File from "@std/io/io.ms"
import IoError from "@std/io/io.ms"
type Holder:
    file: File
    label: String
export fn main() Int:
    opened := files().open("data.txt")
    if opened.is_error():
        return 4
    file := opened.get()

    read := file.read(1)
    if read.is_error():
        return 7
    chunk := read.get()

    match chunk:
        data:
            if data.decode_utf8() != "d":
                return 5
        none:
            return 6

    original := Holder(file: file, label: "original")
    copy := original.clone()
    copy.label = "copy"
    if original.label != "original":
        return 1
    copy.file.close()
    reread := original.file.read(1)
    if reread.is_ok():
        return 3
    cause := reread.err()

    match cause:
        IoError.Closed:
            return 0
        _:
            return 2

