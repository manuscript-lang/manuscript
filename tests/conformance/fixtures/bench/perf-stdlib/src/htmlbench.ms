import bench, words from "./harness.ms"
import parse, escape, unescape from "@std/data/html.ms"

fn html_doc(count Int) String:
    var sb = ""
    sb += "<div>"
    for i in 0..count:
        sb += f"<p class=\"row\" id=\"r{i}\">item <b>{i}</b> &amp; more</p>"
    sb += "</div>"
    return sb

export fn bench_html() Void:
    html := html_doc(2000)

    bench(
        "html.parse",
        2000,
        fn() Int:
            if parse(html).is_ok():
                return 1

            return 0
    )

    text := words(2000).join(" <&> ")
    bench(
        "html.escape_unescape", 2000,
        fn() Int: return text | escape | unescape | .length()
    )
