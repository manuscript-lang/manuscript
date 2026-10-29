import {terminal, TerminalEvent, EraseRegion} from "@std/io.ms"
import stdout from "@std/io.ms"
import nanoseconds from "@std/time.ms"

fn describe(e: TerminalEvent) String:
    match e:
        Text(t): return "text:" + t
        Key(n, c, a, s): return "key:" + n + " ctrl={c} alt={a} shift={s}"
        Resize(c, r): return "resize:{c}x{r}"

export fn main() Int:
    let raw = terminal().raw_mode(alternate_screen: false)

    if let t = raw:
        var term = t
        let _ = term.move_cursor(1, 2)
        let _ = term.show_cursor(false)
        let _ = term.erase(EraseRegion.LineEnd)
        if let size = term.size():
            let _ = stdout().write("size {size.columns}x{size.rows}\r\n")

        var done = false

        while not done:
            let next = term.next_event(nanoseconds(5000000000))

            if let maybe = next:
                if let e = maybe:
                    let _ = stdout().write(describe(e.clone()) + "\r\n")
                    done = describe(e) == "text:q"
                else:
                    let _ = stdout().write("timeout\r\n")
                    done = true
            else:
                let _ = stdout().write("error\r\n")
                done = true

        term.close()
        return 0

    let _ = stdout().write("no raw mode\n")
    return 1
