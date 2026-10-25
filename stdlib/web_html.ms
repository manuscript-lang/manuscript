from "@std/shared.ms" import share
from "@std/core.ms" import Closeable
from "@std/web.ms" import html_text, html
from "@std/http.ms" import Response, HttpError, stream_response
from "@std/bytes.ms" import BytesBuilder
from "@std/io.ms" import WriteStream, IoError

# Explicit HTML tree. Text and ordinary attributes are escaped; executable markup requires Trusted.
export type Html:
    # Text-node content, escaped for HTML.
    case Text(
        # Untrusted text escaped before insertion into HTML.
        value: String
    )
    # A supported ordinary element with validated attributes and nested children.
    case Element(
        # Lowercase HTML tag; script/style and custom executable contexts are excluded.
        tag: String,
        # Attribute values are quoted and escaped; event/style/srcdoc attributes are rejected.
        attributes: Map[String, String],
        # Child nodes in document order.
        children: List[Html]
    )
    # Explicitly trusted application markup; never interpolate untrusted strings here.
    case Trusted(
        # Complete trusted markup, still subject to byte limits.
        markup: String
    )

# Bounds for one render, including trusted markup and escaped output expansion.
export type HtmlLimits:
    # Maximum encoded output bytes.
    max_bytes: Int = 1048576
    # Maximum visited nodes in one render; defaults to 4096.
    max_nodes: Int = 4096
    # Maximum nesting depth, with an absolute maximum of 128.
    max_depth: Int = 64

type Rendering:
    bytes: BytesBuilder
    remaining: Int
    nodes: Int
    depth: Int

impl Rendering:
    var def append(text: String) -> Result[Unit, HttpError]:
        if text.byte_length() > self.remaining: return error(HttpError.LimitExceeded)

        self.remaining -= text.byte_length()
        self.bytes.concat(text.to_bytes())
        return ok(())

    var def escaped(text: String) -> Result[Unit, HttpError]:
        if text.byte_length() > self.remaining: return error(HttpError.LimitExceeded)

        # Bound before escaping; expansion is checked before appending.
        return self.append(html_text(text))

def valid_attribute(name: String, value: String) -> Bool:
    if (
        name == ""
        or name.starts_with("on")
        or ["style", "srcdoc", "xmlns", "xlink:href"].contains(name)
    ): return False

    for char in name.chars():
        if not "abcdefghijklmnopqrstuvwxyz0123456789-_".contains(char): return False

    if ["href", "src", "action", "formaction", "poster", "cite", "background"].contains(
        name
    ):
        for code in value.scalar_values():
            if code <= 32 or code == 127 or code == 92: return False
        if value.starts_with("//"): return False
        if (
            value.contains(":")
            and not value.starts_with("https://")
            and not value.starts_with("http://")
        ): return False

    if ["srcset", "ping"].contains(name): return False

    return True

def render_node(node: Html, var state: Rendering, depth: Int) -> Result[Unit, HttpError]:
    if state.nodes <= 0 or depth > state.depth: return error(HttpError.LimitExceeded)

    state.nodes -= 1

    match node:
        case Text(value): return state.escaped(value)
        case Trusted(markup): return state.append(markup)
        case Element(tag, attributes, children): return render_element(
            tag, attributes, children, var state, depth
        )

def render_element(
    tag: String,
    attributes: Map[String, String],
    children: List[Html],
    var state: Rendering,
    depth: Int
) -> Result[Unit, HttpError]:
    let tags = "html head body title meta link main header footer nav section article aside div span p a strong em b i u small code pre blockquote ul ol li dl dt dd table caption thead tbody tfoot tr th td h1 h2 h3 h4 h5 h6 form label input button select option textarea fieldset legend img picture source video audio track br hr wbr details summary time figure figcaption dialog progress meter output template".split(
        " "
    )
    if not tags.contains(tag): return error(HttpError.InvalidInput)
    if tag == "meta" and attributes.contains("http-equiv"): return error(
        HttpError.InvalidInput
    )

    let void = ["meta", "link", "input", "img", "source", "track", "br", "hr", "wbr"].contains(
        tag
    )
    if void and children.length() != 0: return error(HttpError.InvalidInput)

    try state.append("<" + tag)

    for field in attributes.entries():
        if not valid_attribute(field.key, field.value): return error(
            HttpError.InvalidInput
        )

        try state.append(" " + field.key + "=\"")
        try state.escaped(field.value)
        try state.append("\"")

    try state.append(">")
    if void: return ok(())

    for child in children: try render_node(child, var state, depth + 1)
    return state.append("</" + tag + ">")

# Renders escaped, validated markup under finite byte/node/depth bounds.
export def render_html(
    node: Html,
    limits: HtmlLimits = HtmlLimits()
) -> Result[String, HttpError]:
    msrt_shield_enter()

    with HtmlRendering() as rendering:
        if (
            limits.max_bytes < 0
            or limits.max_nodes < 0
            or limits.max_depth < 0
            or limits.max_depth > 128
        ): return error(HttpError.InvalidInput)

        var state = Rendering(
            BytesBuilder(), limits.max_bytes, limits.max_nodes, limits.max_depth
        )
        try render_node(node, var state, 0)
        return ok(state.bytes.freeze().decode_utf8().get().clone())

# Renders a buffered HTML response; errors are returned before a response is committed.
export def html_response(
    node: Html,
    status: Int = 200,
    limits: HtmlLimits = HtmlLimits()
) -> Result[Response, HttpError]:
    return ok(html(try render_html(node, limits), status))

# Streams ordered independently rendered fragments, flushing after each fragment.
# The byte budget covers the whole response; node/depth budgets apply per fragment.
export def html_stream(
    fragments: List[Html],
    status: Int = 200,
    limits: HtmlLimits = HtmlLimits()
) -> Response:
    return stream_response(
        lambda (output: WriteStream): write_fragments(
            output, fragments, limits
        ),
        content_type: "text/html; charset=utf-8",
        status: status
    )

def write_fragments(
    output: WriteStream,
    fragments: List[Html],
    limits: HtmlLimits
) -> Result[Unit, IoError]:
    with HtmlHeld(share(output)) as destination:
        var remaining = limits.max_bytes + 0
        var index = 0

        while index < fragments.length():
            with HtmlHeld(
                render_html(
                    fragments[index],
                    HtmlLimits(
                        remaining, limits.max_nodes, limits.max_depth
                    )
                )
            ) as rendered:
                if rendered.value.is_error(): return error(IoError.InvalidData)

                remaining -= rendered.value.get().byte_length()
                try destination.value.get().write(rendered.value.get())
                try destination.value.get().flush()

            index += 1

        return ok(())

type HtmlHeld[T]:
    value: T

impl Closeable for HtmlHeld[T]:
    var def close() -> Unit: ()

extern def msrt_shield_enter() -> Unit

extern def msrt_shield_exit() -> Unit

type HtmlRendering:
    active: Bool = True

impl Closeable for HtmlRendering:
    var def close() -> Unit: msrt_shield_exit()
