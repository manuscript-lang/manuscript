# conform: tags=interfaces,optional,stdlib-io,stdlib-streams,tier-stdlib,try-result
# conform: phase=run
from "@std/streams.ms" import from_bytes, read_lines
from "@std/io.ms" import stdout

# read_lines drains the stream, strips LF and CRLF endings, and keeps interior empty lines.
export def main() -> Int:
    let lines = read_lines(from_bytes("one\r\ntwo\n\nlast".to_bytes(), 4)).get()
    for line in lines:
        stdout().write(f"[{line}]\n").get()
    return 0
