import StringBuilder from "@std/string_builder.ms"

fn f() String:
    var sb = StringBuilder()
    sb.append("a")

    text := sb.build()  // error: used again
    sb.append("b")
    return text
