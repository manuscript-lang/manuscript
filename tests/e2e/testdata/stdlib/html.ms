import escape from "@std/html.ms"
import panic from "@std/faults.ms"

test "HTML escaping preserves Unicode and escapes all markup characters":
    if escape("<&>\"'") != "&lt;&amp;&gt;&#34;&#39;": return panic("HTML entities")
    if escape("é🙂") != "é🙂": return panic("Unicode changed")
    if escape("") != "": return panic("empty HTML")
