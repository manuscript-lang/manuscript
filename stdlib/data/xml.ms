import StringBuilder, from_scalars from "@std/string.ms"
import parse_int_radix from "@std/text.ms"

# XML documents as a tree of elements, text and comments, parsed and written in Manuscript.
# `parse` accepts well-formed XML 1.0 without DTD processing (a DOCTYPE is skipped, entities beyond
# the five predefined and numeric references are rejected). Names keep their prefix as written
# (`svg:rect`); namespaces are not resolved. `stringify` writes a tree back with escaping.
#
#     import parse, stringify, XmlNode from "@std/data/xml.ms"
#     let doc = parse("<feed><item id=\"1\">Hi &amp; bye</item></feed>").get()
#     let item = doc.find("item").get()
#     item.attribute("id")           # "1"
#     item.text()                    # "Hi & bye"

# Errors returned for malformed XML or a nesting budget that was exceeded.
export type XmlError:
    # The depth budget is not positive.
    case InvalidInput
    # The text is not well-formed: unbalanced or mismatched tags, bad names, attributes or references.
    case InvalidData
    # Element nesting is deeper than the supplied budget.
    case LimitExceeded

# An XML attribute with its decoded value.
export type XmlAttribute:
    # Attribute name as written, including any prefix.
    name: String
    # Attribute value with references decoded.
    value: String

# A node of a parsed XML tree.
export type XmlNode:
    # An element with its attributes in source order and its child nodes.
    case XmlElement(
        # Tag name as written, including any prefix.
        name: String,
        # Attributes in source order.
        attributes: List[XmlAttribute],
        # Child elements, text and comments in document order.
        children: List[XmlNode]
    )
    # Character data with references decoded; CDATA sections become text.
    case XmlText(
        # Text with entity and character references decoded.
        text: String
    )
    # A comment, without the delimiters.
    case XmlComment(
        # Comment contents exactly as written between the delimiters.
        text: String
    )

impl XmlNode:
    # The tag name of an element, or empty text for text and comments.
    fn tag() String:
        match self:
            XmlElement(name, _, _): return name.clone()
            _: return ""

    # Returns the value of an attribute of an element, or none.
    fn attribute(name: String) String?:
        match self:
            XmlElement(_, attributes, _):
                for attribute in attributes:
                    if attribute.name == name: return attribute.value.clone()
                return none
            _: return none

    # Returns the child nodes of an element, or an empty list. The result is an owned copy.
    fn children() List[XmlNode]:
        match self:
            XmlElement(_, _, children): return children.clone()
            _: return List[XmlNode]()

    # Returns all descendant text joined in document order, without comments.
    fn text() String:
        var out = StringBuilder()
        collect_text(self, var out)
        return out.build()

    # Returns the first direct child element named `name`, or none. The result is an owned copy.
    fn find(name: String) XmlNode?:
        match self:
            XmlElement(_, _, children):
                for child in children:
                    if child.tag() == name: return child.clone()
                return none
            _: return none

    # Returns every direct child element named `name`, in order.
    fn find_all(name: String) List[XmlNode]:
        var found = List[XmlNode]()

        match self:
            XmlElement(_, _, children):
                for child in children:
                    if child.tag() == name: found.append(child.clone())
            _: return found

        return found

fn collect_text(node: XmlNode, var out: StringBuilder) Unit:
    match node:
        XmlText(text): out.append(text)
        XmlElement(_, _, children):
            for child in children:
                collect_text(child, var out)
        _: return

# A cursor over the document's scalars.
type Reader:
    chars: List[String]
    at: Int
    max_depth: Int

impl Reader:
    fn peek(offset: Int = 0) String:
        return self.chars.get(self.at + offset, "")

    fn looking_at(literal: String) Bool:
        let wanted = literal.chars()
        for k in 0..wanted.length():
            if self.peek(k) != wanted[k]: return false
        return true

    fn done() Bool:
        return self.at >= self.chars.length()

    var fn skip_space() Unit:
        while not self.done() and is_space(self.peek()):
            self.at += 1

    # Consumes `literal` or fails.
    var fn expect(literal: String) Unit!XmlError:
        if not self.looking_at(literal): return error(XmlError.InvalidData)

        self.at += literal.chars().length()
        return ok(unit)

    # Returns the text up to `stop` and consumes it, or fails when `stop` never appears.
    var fn take_until(stop: String) String!XmlError:
        var out = StringBuilder()

        while not self.done():
            if self.looking_at(stop):
                self.at += stop.chars().length()
                return ok(out.build())

            out.append(self.peek())
            self.at += 1

        return error(XmlError.InvalidData)

    var fn name() String!XmlError:
        var out = StringBuilder()
        var first = true

        while not self.done():
            let c = self.peek()
            if not is_name_char(c, first): break

            out.append(c)
            first = false
            self.at += 1

        if first: return error(XmlError.InvalidData)

        return ok(out.build())

    # Skips the XML declaration, comments, processing instructions and DOCTYPE before and after the root.
    var fn skip_misc() Unit!XmlError:
        while true:
            self.skip_space()

            if self.looking_at("<?"):
                self.at += 2

                let _pi = try self.take_until("?>")
            else if self.looking_at("<!--"):
                self.at += 4

                let _comment = try self.take_until("-->")
            else if self.looking_at("<!DOCTYPE"):
                var depth = 0

                while not self.done():
                    let c = self.peek()
                    self.at += 1
                    if c == "[": depth += 1
                    if c == "]": depth -= 1
                    if c == ">" and depth <= 0: break
            else:
                break

        return ok(unit)

    var fn element(depth: Int) XmlNode!XmlError:
        if depth > self.max_depth: return error(XmlError.LimitExceeded)

        try self.expect("<")

        let name = try self.name()
        var attributes = List[XmlAttribute]()

        while true:
            self.skip_space()

            if self.looking_at("/>"):
                self.at += 2
                return ok(XmlElement(name, attributes, List[XmlNode]()))

            if self.looking_at(">"):
                self.at += 1
                break

            let attribute_name = try self.name()
            self.skip_space()
            try self.expect("=")
            self.skip_space()

            let quote = self.peek()
            if quote != "\"" and quote != "'": return error(XmlError.InvalidData)

            self.at += 1

            let raw = try self.take_until(quote)
            if raw.contains("<"): return error(XmlError.InvalidData)

            for existing in attributes:
                if existing.name == attribute_name: return error(XmlError.InvalidData)
            attributes.append(
                XmlAttribute(
                    name: attribute_name, value: try decode(raw)
                )
            )

        var children = List[XmlNode]()

        while true:
            if self.done(): return error(XmlError.InvalidData)

            if self.looking_at("</"):
                self.at += 2

                let closing = try self.name()
                if closing != name: return error(XmlError.InvalidData)

                self.skip_space()
                try self.expect(">")
                return ok(XmlElement(name, attributes, children))

            if self.looking_at("<!--"):
                self.at += 4
                children.append(XmlComment(try self.take_until("-->")))
            else if self.looking_at("<![CDATA["):
                self.at += 9
                children.append(XmlText(try self.take_until("]]>")))
            else if self.looking_at("<?"):
                self.at += 2

                let _pi = try self.take_until("?>")
            else if self.looking_at("<"):
                children.append(try self.element(depth + 1))
            else:
                var text = StringBuilder()

                while not self.done() and self.peek() != "<":
                    text.append(self.peek())
                    self.at += 1

                children.append(XmlText(try decode(text.build())))

fn is_space(c: String) Bool:
    return c == " " or c == "\t" or c == "\n" or c == "\r"

fn is_name_char(c: String, first: Bool) Bool:
    if c.is_empty() or is_space(c): return false
    if c.contains_any("<>/=\"'&!?;,()[]\{\}"): return false
    if first and (c.contains_any("-.0123456789")): return false

    return true

# Decodes the five predefined entities and numeric references; any other `&name;` is invalid.
fn decode(text: String) String!XmlError:
    if not text.contains("&"): return ok(text.clone())

    var out = StringBuilder()
    var rest = text.clone()

    while true:
        let at = rest.index_of("&")

        if not at.is_some():
            out.append(rest)
            break

        out.append(rest.take(at.get(0)))

        let tail = rest.drop(at.get(0) + 1)
        let end = tail.index_of(";")
        if not end.is_some(): return error(XmlError.InvalidData)

        let entity = tail.take(end.get(0))
        rest = tail.drop(end.get(0) + 1)

        if entity == "lt": out.append("<")
        else if entity == "gt": out.append(">")
        else if entity == "amp": out.append("&")
        else if entity == "quot": out.append("\"")
        else if entity == "apos": out.append("'")
        else if entity.starts_with("#x"):
            out.append(try scalar(parse_int_radix(entity.drop(2), 16)))
        else if entity.starts_with("#"):
            out.append(try scalar(parse_int_radix(entity.drop(1), 10)))
        else:
            return error(XmlError.InvalidData)

    return ok(out.build())

fn scalar(value: Int?) String!XmlError:
    if not value.is_some(): return error(XmlError.InvalidData)

    let text = from_scalars([value.get(0)])
    if text.is_error(): return error(XmlError.InvalidData)

    return ok(text.get())

# Parses a document with a single root element and returns that element.
# `max_depth` bounds element nesting (default 1000); deeper input is `LimitExceeded`.
# A document with several roots, text outside the root, or any syntax error is `InvalidData`.
export fn parse(text: String, max_depth: Int = 1000) XmlNode!XmlError:
    if max_depth <= 0: return error(XmlError.InvalidInput)

    var reader = Reader(chars: text.chars(), at: 0, max_depth: max_depth)
    if reader.peek() == "\u{feff}": reader.at += 1
    try reader.skip_misc()

    let root = try reader.element(1)
    try reader.skip_misc()
    if not reader.done(): return error(XmlError.InvalidData)

    return ok(root)

# Escapes `&`, `<` and `>` for text content.
export fn escape_text(text: String) String:
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")

# Escapes text for a double-quoted attribute value.
export fn escape_attribute(text: String) String:
    return escape_text(text).replace("\"", "&quot;").replace("\n", "&#10;").replace(
        "\t", "&#9;"
    )

# Writes a node as XML. A non-empty `indent` (such as two spaces) puts each element on its own
# line, except elements holding text, which stay on one line. An element with no children is self-closing.
export fn stringify(node: XmlNode, indent: String = "") String:
    var out = StringBuilder()
    write(node, indent, 0, var out)
    return out.build()

fn write(node: XmlNode, indent: String, level: Int, var out: StringBuilder) Unit:
    let pad = if indent.is_empty(): "" else: indent.repeat(level).get("")
    let newline = if indent.is_empty(): "" else: "\n"

    match node:
        XmlText(text): out.append(escape_text(text))
        XmlComment(text): out.append("{pad}<!--{text}-->{newline}")
        XmlElement(name, attributes, children):
            out.append("{pad}<{name}")
            for attribute in attributes:
                out.append(" {attribute.name}=\"{escape_attribute(attribute.value)}\"")

            if children.is_empty():
                out.append("/>{newline}")
                return

            var has_text = false
            for child in children:
                if child.tag().is_empty() and child.text() != "": has_text = true

            if has_text or indent.is_empty():
                out.append(">")
                for child in children:
                    write(child, "", 0, var out)
                out.append("</{name}>{newline}")
            else:
                out.append(">{newline}")
                for child in children:
                    write(child, indent, level + 1, var out)
                out.append("{pad}</{name}>{newline}")

impl Error for XmlError:
    # Returns an XML-prefixed diagnostic without echoing the source.
    fn message() String:
        match self:
            InvalidInput: return "XML: invalid input"
            InvalidData: return "XML: invalid data"
            LimitExceeded: return "XML: limit exceeded"
