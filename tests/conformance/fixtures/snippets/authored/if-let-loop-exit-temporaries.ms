// conform: tags=control-flow,tier-core
// conform: phase=run
// conform: origin=break and continue in if let bodies and else branches with condition temporaries

fn maybe(name: String, present: Bool) List[String]?:
    return if present: [name.clone()] else: none

fn stop_in_body() Void:
    for i in 0..3:
        if r := maybe(f"body{i}", true):
            if i == 1:
                break

            print(f"{r[0]}")

fn skip_in_body() Void:
    for i in 0..3:
        if r := maybe(f"skip{i}", true):
            if i == 1:
                continue

            print(f"{r[0]}")

fn stop_in_else() Void:
    for i in 0..3:
        if r := maybe(f"else{i}", i == 0):
            print(f"{r[0]}")
        else:
            break

fn skip_in_else() Void:
    for i in 0..3:
        if r := maybe(f"else{i}", i != 1):
            print(f"{r[0]}")
        else:
            continue

fn main() Void:
    stop_in_body()
    skip_in_body()
    stop_in_else()
    skip_in_else()
