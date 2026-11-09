// conform: tags=control-flow,tier-core
// conform: phase=run
// conform: origin=break and continue in if let bodies and else branches with condition temporaries

fn maybe(name: String, present: Bool) List[String]?:
    return if present: [name] else: none

fn stop_in_body() Unit:
    for i in 0..3:
        if let r = maybe("body{i}", true):
            if i == 1:
                break

            print("{r[0]}")

fn skip_in_body() Unit:
    for i in 0..3:
        if let r = maybe("skip{i}", true):
            if i == 1:
                continue

            print("{r[0]}")

fn stop_in_else() Unit:
    for i in 0..3:
        if let r = maybe("else{i}", i == 0):
            print("{r[0]}")
        else:
            break

fn skip_in_else() Unit:
    for i in 0..3:
        if let r = maybe("else{i}", i != 1):
            print("{r[0]}")
        else:
            continue

export fn main() Int:
    stop_in_body()
    skip_in_body()
    stop_in_else()
    skip_in_else()
    return 0
