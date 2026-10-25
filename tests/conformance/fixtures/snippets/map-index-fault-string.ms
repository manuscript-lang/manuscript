# conform: tags=maps,faults,tier-core
# conform: phase=run
# conform: origin=Map and Bytes indexing
from "@std/io.ms" import stdout

export def main() -> Int:
    let scores = {"ann": 1, "bob": 2}
    stdout().write(f"{scores["ann"]}\n")
    stdout().write(f"{scores["eve"]}\n")
    return 0
