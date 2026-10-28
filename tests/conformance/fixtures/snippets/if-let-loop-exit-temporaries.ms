# conform: tags=control-flow,tier-core
# conform: phase=run
# conform: origin=break and continue in if let bodies and else branches with condition temporaries
from "@std/io.ms" import stdout

def maybe(name: String, present: Bool) -> Optional[List[String]]:
    return some([name]) if present else none

def stop_in_body() -> Unit:
    for i in 0..3:
        if let r = maybe(f"body{i}", True):
            if i == 1:
                break

            stdout().write(f"{r[0]}\n").get()

def skip_in_body() -> Unit:
    for i in 0..3:
        if let r = maybe(f"skip{i}", True):
            if i == 1:
                continue

            stdout().write(f"{r[0]}\n").get()

def stop_in_else() -> Unit:
    for i in 0..3:
        if let r = maybe(f"else{i}", i == 0):
            stdout().write(f"{r[0]}\n").get()
        else:
            break

def skip_in_else() -> Unit:
    for i in 0..3:
        if let r = maybe(f"else{i}", i != 1):
            stdout().write(f"{r[0]}\n").get()
        else:
            continue

export def main() -> Int:
    stop_in_body()
    skip_in_body()
    stop_in_else()
    skip_in_else()
    return 0
