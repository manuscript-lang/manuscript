import StringBuilder from "@std/string.ms"

fn f() String:
    var sb = StringBuilder()
    sb.append("a")

    let text = sb.build()  # error: used again
    sb.append("b")
    return text
