import HtmlLimits, HtmlNode from "@std/data/html.ms"

export extern fn msstd_html_escape(text: String) String

export extern fn msstd_html_unescape(text: String) String

export extern fn msstd_html_parse(text: String, limits: HtmlLimits?) HtmlNode!
