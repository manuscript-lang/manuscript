import {bench, words} from "./harness.ms"
import StringBuilder from "@std/string.ms"
import {parse, escape, unescape} from "@std/html.ms"

fn html_doc(count: Int) String:
    var sb = StringBuilder()
    sb.append("<div>")
    for i in 0..count:
        sb.append("<p class=\"row\" id=\"r{i}\">item <b>{i}</b> &amp; more</p>")
    sb.append("</div>")
    return sb.build()

export fn bench_html() Unit:
    let html = html_doc(2000)

    bench(
        "html.parse",
        2000,
        fn() Int:
            if parse(html).is_ok():
                return 1

            return 0
    )

    let text = words(2000).join(" <&> ")
    bench(
        "html.escape_unescape", 2000,
        fn() Int: return text | escape | unescape | .length()
    )
