# conform: tags=interfaces,optional,stdlib-io,stdlib-streams,tier-stdlib,try-result
# conform: phase=run
import from_bytes, read_lines from "@std/io/streams.ms"
import stdout from "@std/io/io.ms"

# read_lines drains the stream, strips LF and CRLF endings, and keeps interior empty lines.
export fn main() Int:
    let lines = read_lines(from_bytes("one\r\ntwo\n\nlast".to_bytes(), 4)).get()
    for line in lines:
        stdout().write("[{line}]\n").get()
    return 0
