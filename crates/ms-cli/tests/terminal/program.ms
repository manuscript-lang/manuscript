from "@std/io.ms" import terminal, TerminalEvent, EraseRegion
from "@std/io.ms" import stdout
from "@std/time.ms" import nanoseconds

def describe(e: TerminalEvent) -> String:
    match e:
        case Text(t): return "text:" + t
        case Key(n, c, a, s): return "key:" + n + f" ctrl={c} alt={a} shift={s}"
        case Resize(c, r): return f"resize:{c}x{r}"

export def main() -> Int:
    let raw = terminal().raw_mode(alternate_screen: False)

    if let t = raw:
        var term = t
        let _ = term.move_cursor(1, 2)
        let _ = term.show_cursor(False)
        let _ = term.erase(EraseRegion.LineEnd)
        if let size = term.size():
            let _ = stdout().write(f"size {size.columns}x{size.rows}\r\n")

        var done = False

        while not done:
            let next = term.next_event(nanoseconds(5000000000))

            if let maybe = next:
                if let e = maybe:
                    let _ = stdout().write(describe(e.clone()) + "\r\n")
                    done = describe(e) == "text:q"
                else:
                    let _ = stdout().write("timeout\r\n")
                    done = True
            else:
                let _ = stdout().write("error\r\n")
                done = True

        term.close()
        return 0

    let _ = stdout().write("no raw mode\n")
    return 1
