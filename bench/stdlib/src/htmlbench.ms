import {bench, words} from "./harness.ms"
import {StringBuilder} from "@std/string.ms"
import {parse, escape, unescape} from "@std/html.ms"

fn html_doc(count: Int) -> String:
    let sb = StringBuilder()
    sb.append("<div>")
    var i = 0

    while i < count:
        sb.append("<p class=\"row\" id=\"r{i}\">item <b>{i}</b> &amp; more</p>")
        i = i + 1

    sb.append("</div>")
    return sb.freeze()

export fn bench_html() -> Unit:
    let html = html_doc(2000)
    bench(
        "html.parse",
        2000,
        fn() -> Int:
            if parse(text: html).is_ok(): return 1

            return 0
    )
    let text = words(2000).join(separator: " <&> ")
    bench(
        "html.escape_unescape",
        2000,
        fn() -> Int:
            return unescape(text: escape(text: text)).length()
    )
