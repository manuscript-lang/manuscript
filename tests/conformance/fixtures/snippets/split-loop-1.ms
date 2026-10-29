# conform: tags=strings,lists,control-flow,tier-stdlib
# conform: phase=run
# conform: origin=perf: split loops yield pieces one at a time; a kept piece must stay intact
import stdout from "@std/io.ms"

fn say(text: String) Unit:
    let _ignored = stdout().write(text)

fn keep(text: String) List[String]:
    var out: List[String] = []
    for p in text.split(","):
        out.append(p)
    return out

fn first_long(text: String) String:
    for p in text.split(","):
        if p.length() > 3:
            return p
    return "none"

fn count(text: String) Int:
    var n = 0

    for p in text.split(","):
        if p == "skip":
            continue
        if p == "stop":
            break

        n += p.length()

    return n

export fn main() Int:
    let a = keep("aa,bbbb,c,,dddddd,eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee,f")
    for x in a:
        say("[{x}]")
    say(
        "\n{first_long("a,bbbbb,cc")} {first_long("a,b")} {count("ab,skip,cde,stop,zzz")}\n"
    )

    var t = 0
    for q in "héllo wörld".split(""):
        t += q.length()
    for q in "a,b,c,d".split(",", max_parts: 2):
        say("<{q}>")
    for q in "".split(","):
        say("<{q}>")
    say("\n{t}\n")
    say(
        "{let_form("ab,c,,defgh")} {let_kept("ab,c")} {nested("a,bb;ccc,dddd,e;")} {closure_keeps("x,yyyy,zz,wwwwwwwwwwwwwwwwwwwwwwwwwwwwwwww")}\n"
    )
    for q in "a,b".split(",", max_parts: 0):
        say("never")

    for q in "p,q,r".split(","):
        for r in "1-2".split("-"):
            if q == "q":
                break

            say("{q}{r} ")

    say("\n")
    return 0

fn let_form(text: String) Int:
    let parts = text.split(",")
    var total = 0
    for p in parts:
        total += p.length()
    return total

fn let_kept(text: String) Int:
    let parts = text.split(",")
    var total = 0
    for p in parts:
        total += p.length()
    return total + parts.length()

fn nested(text: String) Int:
    var total = 0
    for line in text.split(";"):
        for cell in line.split(","):
            total += cell.length()
    return total

fn closure_keeps(text: String) Int:
    var fs: List[fn() Int] = []
    for p in text.split(","):
        fs.append(fn() Int: return p.length())

    var t = 0
    for f in fs:
        t += f()
    return t
