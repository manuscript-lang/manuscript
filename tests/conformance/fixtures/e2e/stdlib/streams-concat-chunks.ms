# conform: tags=interfaces,optional,stdlib-io,stdlib-streams,tier-stdlib,try-result
# conform: phase=run
from "@std/streams.ms" import from_bytes, concat, digest
from "@std/io.ms" import read_all, stdout
from "@std/crypto.ms" import HashAlgorithm

def say(text: String) -> Unit:
    stdout().write(text).get()

# A stream is a value: concat must read its inputs in place so each keeps its position across chunks.
export def main() -> Int:
    let data = "hello world".to_bytes()
    let joined = concat([from_bytes(data.clone(), 4), from_bytes(data.clone(), 4)])
    let all = read_all(joined).get()
    say(f"joined {all.length()}\n")

    var again = concat([from_bytes(data.clone(), 3), from_bytes(data, 5)])
    say(f"digest {digest(var again, HashAlgorithm.Sha256).get().length()}\n")
    return 0
