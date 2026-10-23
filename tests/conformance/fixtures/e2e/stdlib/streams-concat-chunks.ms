# conform: tags=interfaces,optional,stdlib-io,stdlib-streams,tier-stdlib,try-result
# conform: phase=run
import {from_bytes, concat, digest} from "@std/streams.ms"
import {read_all, stdout} from "@std/io.ms"
import {HashAlgorithm} from "@std/crypto.ms"

fn say(text: String) Unit:
    stdout().write(text).get()

# A stream is a value: concat must read its inputs in place so each keeps its position across chunks.
export fn main() Int:
    let data = "hello world".to_bytes()
    let joined = concat([from_bytes(data, 4), from_bytes(data, 4)])
    let all = read_all(joined).get()
    say("joined {all.length()}\n")

    let again = concat([from_bytes(data, 3), from_bytes(data, 5)])
    say("digest {digest(again, HashAlgorithm.Sha256).get().length()}\n")
    return 0
