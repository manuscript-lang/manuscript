import HtmlError, HtmlLimits, HtmlNode from "@std/data/html.ms"

export extern fn msrt_html_escape(text: String) String

export extern fn msrt_html_unescape(text: String) String

export extern fn msrt_html_parse(text: String, limits: HtmlLimits?) HtmlNode!HtmlError
