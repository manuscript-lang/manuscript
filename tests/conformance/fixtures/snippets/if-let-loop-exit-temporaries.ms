# conform: tags=control-flow,tier-core
# conform: phase=run
# conform: origin=break and continue in if let bodies and else branches with condition temporaries
import stdout from "@std/io.ms"

fn maybe(name: String, present: Bool) Optional[List[String]]:
    return if present: some([name]) else: none

fn stop_in_body() Unit:
    for i in 0..3:
        if let r = maybe("body{i}", true):
            if i == 1:
                break

            stdout().write("{r[0]}\n").get()

fn skip_in_body() Unit:
    for i in 0..3:
        if let r = maybe("skip{i}", true):
            if i == 1:
                continue

            stdout().write("{r[0]}\n").get()

fn stop_in_else() Unit:
    for i in 0..3:
        if let r = maybe("else{i}", i == 0):
            stdout().write("{r[0]}\n").get()
        else:
            break

fn skip_in_else() Unit:
    for i in 0..3:
        if let r = maybe("else{i}", i != 1):
            stdout().write("{r[0]}\n").get()
        else:
            continue

export fn main() Int:
    stop_in_body()
    skip_in_body()
    stop_in_else()
    skip_in_else()
    return 0
