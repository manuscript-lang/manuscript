import keep, measure from "@std/bench.ms"
import words from "./src/harness.ms"
import StringBuilder from "@std/string.ms"
import parse, escape, unescape from "@std/html.ms"

fn html_doc(count: Int) String:
    var sb = StringBuilder()
    sb.append("<div>")
    for i in 0..count:
        sb.append("<p class=\"row\" id=\"r{i}\">item <b>{i}</b> &amp; more</p>")
    sb.append("</div>")
    return sb.build()

bench "html.parse":
    let html = html_doc(2000)

    fn work() Result[Unit, Error]:
        if parse(html).is_ok():
            return keep(1)

        return keep(0)

    try measure(2000, work)

bench "html.escape_unescape":
    let text = words(2000).join(" <&> ")
    try measure(2000, fn: keep(text | escape | unescape | .length()))
