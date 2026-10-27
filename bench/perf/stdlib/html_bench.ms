from "@std/bench.ms" import keep, measure
from "@std/collections.ms" import range
from "./src/harness.ms" import words
from "@std/string.ms" import StringBuilder
from "@std/html.ms" import parse, escape, unescape

def html_doc(count: Int) -> String:
    var sb = StringBuilder()
    sb.append("<div>")
    for i in range(0, count):
        sb.append(f"<p class=\"row\" id=\"r{i}\">item <b>{i}</b> &amp; more</p>")
    sb.append("</div>")
    return sb.build()

bench "html.parse":
    let html = html_doc(2000)

    def work() -> Result[Unit, Error]:
        if parse(html).is_ok():
            return keep(1)

        return keep(0)

    try measure(2000, work)

bench "html.escape_unescape":
    let text = words(2000).join(" <&> ")
    try measure(2000, lambda: keep(text | escape | unescape | .length()))
