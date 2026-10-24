from "@std/collections.ms" import range
from "./harness.ms" import bench, words
from "@std/string.ms" import StringBuilder
from "@std/html.ms" import parse, escape, unescape

def html_doc(count: Int) -> String:
    var sb = StringBuilder()
    sb.append("<div>")
    for i in range(0, count):
        sb.append(f"<p class=\"row\" id=\"r{i}\">item <b>{i}</b> &amp; more</p>")
    sb.append("</div>")
    return sb.freeze()

export def bench_html() -> Unit:
    let html = html_doc(2000)

    bench(
        "html.parse",
        2000,
        lambda () -> Int:
            if parse(html).is_ok():
                return 1

            return 0
    )

    let text = words(2000).join(" <&> ")
    bench(
        "html.escape_unescape", 2000,
        lambda () -> Int: return text | escape | unescape | .length()
    )
