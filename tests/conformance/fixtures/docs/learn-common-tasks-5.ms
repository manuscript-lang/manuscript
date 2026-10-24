# conform: tags=control-flow,interpolation,modules,stdlib-io,tier-core,try-result
# conform: phase=run
# conform: origin=documentation/learn/common-tasks.md:120
from "@std/io.ms" import stdin, stdout, read_line

def run() -> Result[Unit, Error]:
    let input = stdin()

    while True:
        let line = try read_line(input, max_bytes: 4096)

        if let text = line:
            try stdout().write(f"{text}\n")
        else:
            break

    return stdout().flush()

export def main() -> Int:
    if run().is_error():
        return 1

    return 0
