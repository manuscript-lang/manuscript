import HtmlTree from "@std/data/html.ms"

// Native parse bounds; `parse` builds them from `HtmlOptions`.
export type HtmlLimits:
    max_bytes: Int?
    max_depth: Int?
    max_nodes: Int?

export extern fn msstd_html_escape(text: String) String

export extern fn msstd_html_unescape(text: String) String

export extern fn msstd_html_parse(text: String, limits: HtmlLimits) HtmlTree!

export extern fn msstd_html_root(tree: HtmlTree) Int

export extern fn msstd_html_kind(tree: HtmlTree, id: Int) Int

export extern fn msstd_html_data(tree: HtmlTree, id: Int) String

export extern fn msstd_html_namespace(tree: HtmlTree, id: Int) String

export extern fn msstd_html_doctype_id(tree: HtmlTree, id: Int, which: Int) String

export extern fn msstd_html_first_child(tree: HtmlTree, id: Int) Int

export extern fn msstd_html_next_sibling(tree: HtmlTree, id: Int) Int

export extern fn msstd_html_attr_count(tree: HtmlTree, id: Int) Int

export extern fn msstd_html_attr(tree: HtmlTree, id: Int, index: Int, which: Int) String
