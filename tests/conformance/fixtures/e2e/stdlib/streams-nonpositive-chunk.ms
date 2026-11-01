# conform: tags=optional,stdlib-io,stdlib-streams,tier-stdlib,try-result
# conform: phase=run
import from_bytes from "@std/io/streams.ms"
import read_all, stdout from "@std/io/io.ms"

fn say(text: String) Unit:
    stdout().write(text).get()

# A non-positive chunk size fails every read, even when the caller names its own read size.
export fn main() Int:
    let data = "hello".to_bytes()
    say("zero {read_all(from_bytes(data.clone(), 0))}\n")
    say("negative {read_all(from_bytes(data.clone(), -3))}\n")
    say("empty {read_all(from_bytes("".to_bytes(), 0))}\n")
    say("valid {read_all(from_bytes(data, 2)).get().length()}\n")
    return 0
