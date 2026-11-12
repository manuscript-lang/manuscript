import (
	parse_int from "@std/math/math.ms",
	StringBuilder, from_scalars from "@std/string.ms",
)

// An element with fewer attributes than this checks duplicate names by scanning them.
ATTRIBUTE_SCAN_LIMIT := 16

/*
XML documents as a tree of elements, text and comments, parsed and written in Manuscript.
`parse` accepts well-formed XML 1.0 without DTD processing (a DOCTYPE is skipped, entities beyond
the five predefined and numeric references are rejected). Names keep their prefix as written
(`svg:rect`); namespaces are not resolved. `stringify` writes a tree back with escaping.

    import parse from "@std/data/xml.ms"
    doc := parse("<feed><item id=\"1\">Hi &amp; bye</item></feed>")?
    item := doc.find("item").get()
    print(item.attribute("id").get("")) // "1"
    print(item.text())                  // "Hi & bye"
*/

// An XML attribute with its decoded value.
export type XmlAttribute:
	// Attribute name as written, including any prefix.
	name: String
	// Attribute value with references decoded.
	value: String

// A node of a parsed XML tree.
export enum XmlNode:
	// An element with its attributes in source order and its child nodes.
	XmlElement(
		// Tag name as written, including any prefix.
		name: String,
		// Attributes in source order.
		attributes: List[XmlAttribute],
		// Child elements, text and comments in document order.
		children: List[XmlNode]
	)
	// Character data with references decoded; CDATA sections become text.
	XmlText(
		// Text with entity and character references decoded.
		text: String
	)
	// A comment, without the delimiters.
	XmlComment(
		// Comment contents exactly as written between the delimiters.
		text: String
	)

// The tag name of an element, or empty text for text and comments.
fn XmlNode.tag() String:
	match self:
		XmlElement(name, _, _): return name.clone()
		_: return ""

// Returns the value of an attribute of an element, or none.
fn XmlNode.attribute(name: String) String?:
	match self:
		XmlElement(_, attributes, _):
			for attribute in attributes:
				if attribute.name == name: return attribute.value.clone()
			return none
		_: return none

// Returns the child nodes of an element, or an empty list. The result is an owned
// copy.
fn XmlNode.children() List[XmlNode]:
	match self:
		XmlElement(_, _, children): return children.clone()
		_: return List[XmlNode]()

// Returns all descendant text joined in document order, without comments.
fn XmlNode.text() String:
	var out = StringBuilder()
	collect_text(self, var out)
	return out.build()

// Returns the first direct child element named `name`, or none. The result is an
// owned copy.
fn XmlNode.find(name: String) XmlNode?:
	match self:
		XmlElement(_, _, children):
			for child in children:
				if child.tag() == name: return child.clone()
			return none
		_: return none

// Returns every direct child element named `name`, in order.
fn XmlNode.find_all(name: String) List[XmlNode]:
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

// A cursor over the document's scalars.
type Reader:
	chars: List[String]
	at: Int
	max_depth: Int

fn Reader.peek(offset: Int = 0) String:
	return self.chars.get(self.at + offset, "")

fn Reader.looking_at(literal: String) Bool:
	wanted := literal.chars()
	for k in 0..wanted.length():
		if self.peek(k) != wanted[k]: return false
	return true

fn Reader.done() Bool:
	return self.at >= self.chars.length()

fn var Reader.skip_space() Unit:
	while not self.done() and is_space(self.peek()):
		self.at += 1

// Consumes `literal` or fails.
fn var Reader.expect(literal: String) Unit!:
	if not self.looking_at(literal): return error(
		Error("XML: invalid data", kind: "EBADMSG")
	)

	self.at += literal.chars().length()

// Returns the text up to `stop` and consumes it, or fails when `stop` never
// appears.
fn var Reader.take_until(stop: String) String!:
	var out = StringBuilder()
	wanted := stop.chars()

	while not self.done():
		var matches = true

		for k in 0..wanted.length():
			if self.peek(k) != wanted[k]:
				matches = false
				break

		if matches:
			self.at += wanted.length()
			return ok(out.build())

		out.append(self.peek())
		self.at += 1

	return error(Error("XML: invalid data", kind: "EBADMSG"))

// XML comments cannot contain a double hyphen or end with a hyphen.
fn var Reader.comment() String!:
	self.expect("<!--")?

	text := self.take_until("-->")?
	if text.contains("--") or text.ends_with("-"): return error(
		Error("XML: invalid data", kind: "EBADMSG")
	)

	return ok(text)

fn var Reader.name() String!:
	var out = StringBuilder()
	var first = true

	while not self.done():
		c := self.peek()
		if not is_name_char(c, first): break

		out.append(c)
		first = false
		self.at += 1

	if first: return error(Error("XML: invalid data", kind: "EBADMSG"))

	return ok(out.build())

// The reserved target `xml` belongs to a declaration, never a processing
// instruction.
fn var Reader.instruction() Unit!:
	self.expect("<?")?

	target := self.name()?
	if target.length() == 3 and target.lower() == "xml": return error(
		Error("XML: invalid data", kind: "EBADMSG")
	)
	if not self.looking_at("?>") and not is_space(self.peek()): return error(
		Error("XML: invalid data", kind: "EBADMSG")
	)

	_data := self.take_until("?>")?

// Declaration values are literals, not entity-decoded XML attribute values.
fn var Reader.declaration_attribute() XmlAttribute!:
	name := self.name()?
	self.skip_space()
	self.expect("=")?
	self.skip_space()

	quote := self.peek()
	if quote != "\"" and quote != "'": return error(
		Error("XML: invalid data", kind: "EBADMSG")
	)

	self.at += 1
	return ok(XmlAttribute(name, self.take_until(quote)?))

// XMLDecl: mandatory version, optional encoding, optional standalone, in that
// order.
fn var Reader.declaration() Unit!:
	self.expect("<?xml")?
	if not is_space(self.peek()): return error(
		Error("XML: invalid data", kind: "EBADMSG")
	)

	self.skip_space()

	version := self.declaration_attribute()?
	if version.name != "version" or not is_version(version.value): return error(
		Error("XML: invalid data", kind: "EBADMSG")
	)

	var encoding_seen = false
	var standalone_seen = false

	while true:
		before := self.at
		self.skip_space()

		if self.looking_at("?>"):
			self.at += 2
			return ok(unit)

		if self.at == before: return error(Error("XML: invalid data", kind: "EBADMSG"))

		attribute := self.declaration_attribute()?

		if (attribute.name == "encoding" and not encoding_seen and not standalone_seen):
			if not is_encoding_name(attribute.value): return error(
				Error("XML: invalid data", kind: "EBADMSG")
			)

			encoding_seen = true
		else if attribute.name == "standalone" and not standalone_seen:
			if attribute.value != "yes" and attribute.value != "no": return error(
				Error("XML: invalid data", kind: "EBADMSG")
			)

			standalone_seen = true
		else:
			return error(Error("XML: invalid data", kind: "EBADMSG"))

// Skips a quoted literal; its contents never delimit markup.
fn var Reader.quoted(public_id: Bool = false) Unit!:
	quote := self.peek()
	if quote != "\"" and quote != "'": return error(
		Error("XML: invalid data", kind: "EBADMSG")
	)

	self.at += 1

	text := self.take_until(quote)?

	if public_id:
		for c in text.chars():
			code := c.scalar_at(0)
			alphanumeric := (
				(code >= 0x41 and code <= 0x5a)
				or (code >= 0x61 and code <= 0x7a)
				or (code >= 0x30 and code <= 0x39)
			)
			if not alphanumeric and not " \r\n-'()+,./:=?;!*#@$_%".contains(c):
				return error(Error("XML: invalid data", kind: "EBADMSG"))

// Requires at least one whitespace scalar.
fn var Reader.require_space() Unit!:
	before := self.at
	self.skip_space()
	if self.at == before: return error(Error("XML: invalid data", kind: "EBADMSG"))

// XML 1.0 section 2.8 `intSubset`: declarations, comments, instructions and
// parameter references, with quoted spans skipped so `]` and `>` inside them are
// plain text.
fn var Reader.internal_subset() Unit!:
	while true:
		self.skip_space()

		if self.looking_at("]"):
			self.at += 1
			return ok(unit)

		if self.looking_at("<!--"):
			_comment := self.comment()?
		else if self.looking_at("<?"):
			self.instruction()?
		else if self.looking_at("<!"):
			self.at += 2

			while not self.looking_at(">"):
				if self.done(): return error(
					Error("XML: invalid data", kind: "EBADMSG")
				)

				if self.peek() == "\"" or self.peek() == "'":
					self.quoted()?
				else:
					self.at += 1

			self.at += 1
		else if self.looking_at("%"):
			_reference := self.take_until(";")?
		else:
			return error(Error("XML: invalid data", kind: "EBADMSG"))

// XML 1.0 section 2.8 `doctypedecl`: name, optional external identifier, optional
// internal subset.
fn var Reader.doctype() Unit!:
	self.expect("<!DOCTYPE")?
	self.require_space()?

	_name := self.name()?
	self.skip_space()

	if self.looking_at("SYSTEM"):
		self.at += 6
		self.require_space()?
		self.quoted()?
		self.skip_space()
	else if self.looking_at("PUBLIC"):
		self.at += 6
		self.require_space()?
		self.quoted(public_id: true)?
		self.require_space()?
		self.quoted()?
		self.skip_space()

	if self.looking_at("["):
		self.at += 1
		self.internal_subset()?
		self.skip_space()

	self.expect(">")?

// Only the prolog may have a declaration, before any whitespace or other markup.
// The prolog may also hold one DOCTYPE; it is skipped, never expanded.
fn var Reader.skip_misc(
	declaration_allowed: Bool = false,
	doctype_allowed: Bool = false,
) Unit!:
	start := self.at
	var doctype_open = doctype_allowed

	while true:
		self.skip_space()

		if self.looking_at("<?"):
			if (
				declaration_allowed
				and self.at == start
				and self.looking_at("<?xml")
				and is_space(self.peek(5))
			):
				self.declaration()?
			else:
				self.instruction()?
		else if self.looking_at("<!--"):
			_comment := self.comment()?
		else if doctype_open and self.looking_at("<!DOCTYPE"):
			self.doctype()?
			doctype_open = false
		else:
			break

	return ok(unit)

fn var Reader.element(depth: Int) XmlNode!:
	if depth > self.max_depth: return error(
		Error("XML: limit exceeded", kind: "EOVERFLOW")
	)

	self.expect("<")?

	name := self.name()?
	var attributes = List[XmlAttribute]()
	var seen = Set[String]()

	while true:
		before := self.at
		self.skip_space()

		separated := self.at > before

		if self.looking_at("/>"):
			self.at += 2
			return ok(XmlElement(name, attributes, List[XmlNode]()))

		if self.looking_at(">"):
			self.at += 1
			break

		// Attributes are separated by whitespace, so `a="1"b="2"` is malformed.
		if not separated: return error(Error("XML: invalid data", kind: "EBADMSG"))

		attribute_name := self.name()?
		self.skip_space()
		self.expect("=")?
		self.skip_space()

		quote := self.peek()
		if quote != "\"" and quote != "'": return error(
			Error("XML: invalid data", kind: "EBADMSG")
		)

		self.at += 1

		source := self.take_until(quote)?
		if source.contains("<"): return error(
			Error("XML: invalid data", kind: "EBADMSG")
		)

		// XML 1.0 section 3.3.3: literal tabs and line ends in a value become
		// spaces; references are decoded afterwards.
		raw := source.replace("\n", " ").replace("\t", " ")

		// A short list is scanned; a long one moves to a set so names are checked
		// in constant time.
		if attributes.length() < ATTRIBUTE_SCAN_LIMIT:
			for existing in attributes:
				if existing.name == attribute_name: return error(
					Error("XML: invalid data", kind: "EBADMSG")
				)
		else:
			if seen.is_empty():
				for existing in attributes:
					seen.add(existing.name.clone())
			if seen.contains(attribute_name): return error(
				Error("XML: invalid data", kind: "EBADMSG")
			)

			seen.add(attribute_name.clone())

		attributes.append(XmlAttribute(name: attribute_name, value: decode(raw)?))

	var children = List[XmlNode]()

	while true:
		if self.done(): return error(Error("XML: invalid data", kind: "EBADMSG"))

		if self.looking_at("</"):
			self.at += 2

			closing := self.name()?
			if closing != name: return error(
				Error("XML: invalid data", kind: "EBADMSG")
			)

			self.skip_space()
			self.expect(">")?
			return ok(XmlElement(name, attributes, children))

		if self.looking_at("<!--"):
			children.append(XmlComment(self.comment()?))
		else if self.looking_at("<![CDATA["):
			self.at += 9
			children.append(XmlText(self.take_until("]]>")?))
		else if self.looking_at("<?"):
			self.instruction()?
		else if self.looking_at("<"):
			children.append(self.element(depth + 1)?)
		else:
			var text = StringBuilder()

			while not self.done() and self.peek() != "<":
				text.append(self.peek())
				self.at += 1

			raw := text.build()
			if raw.contains("]]>"): return error(
				Error("XML: invalid data", kind: "EBADMSG")
			)

			children.append(XmlText(decode(raw)?))

fn is_space(c: String) Bool:
	return c == " " or c == "\t" or c == "\n" or c == "\r"

// XML 1.0 processes other 1.x versions using the same grammar (section 2.8).
fn is_version(text: String) Bool:
	if not text.starts_with("1.") or text.length() <= 2: return false

	for code in text.drop(2).scalar_values():
		if code < 0x30 or code > 0x39: return false
	return true

fn is_encoding_name(text: String) Bool:
	var first = true

	for code in text.scalar_values():
		letter := (code >= 0x41 and code <= 0x5a) or (code >= 0x61 and code <= 0x7a)
		extra := (
			(code >= 0x30 and code <= 0x39)
			or code == 0x2e
			or code == 0x5f
			or code == 0x2d
		)
		if not letter and (first or not extra): return false

		first = false

	return not first

// XML 1.0 (Fifth Edition), productions [4] NameStartChar and [4a] NameChar.
fn is_name_char(c: String, first: Bool) Bool:
	if c.is_empty(): return false

	code := c.scalar_at(0)
	if is_name_start(code): return true
	if first: return false

	return (
		code == 0x2d
		or code == 0x2e
		or (code >= 0x30 and code <= 0x39)
		or code == 0xb7
		or (code >= 0x300 and code <= 0x36f)
		or (code >= 0x203f and code <= 0x2040)
	)

fn is_name_start(code: Int) Bool:
	return (
		code == 0x3a
		or (code >= 0x41 and code <= 0x5a)
		or code == 0x5f
		or (code >= 0x61 and code <= 0x7a)
		or (code >= 0xc0 and code <= 0xd6)
		or (code >= 0xd8 and code <= 0xf6)
		or (code >= 0xf8 and code <= 0x2ff)
		or (code >= 0x370 and code <= 0x37d)
		or (code >= 0x37f and code <= 0x1fff)
		or (code >= 0x200c and code <= 0x200d)
		or (code >= 0x2070 and code <= 0x218f)
		or (code >= 0x2c00 and code <= 0x2fef)
		or (code >= 0x3001 and code <= 0xd7ff)
		or (code >= 0xf900 and code <= 0xfdcf)
		or (code >= 0xfdf0 and code <= 0xfffd)
		or (code >= 0x10000 and code <= 0xeffff)
	)

// Decodes the five predefined entities and numeric references; any other `&name;` is
// invalid.
fn decode(text: String) String!:
	if not text.contains("&"): return ok(text.clone())

	var out = StringBuilder()

	// Every piece after the first starts right after an `&`, so each is scanned once.
	pieces := text.split("&")
	out.append(pieces[0])

	var index = 1

	while index < pieces.length():
		tail := pieces[index]
		index += 1

		end := tail.index_of(";")
		if end.is_none(): return error(Error("XML: invalid data", kind: "EBADMSG"))

		entity := tail.take(end.get(0))

		if entity == "lt": out.append("<")
		else if entity == "gt": out.append(">")
		else if entity == "amp": out.append("&")
		else if entity == "quot": out.append("\"")
		else if entity == "apos": out.append("'")
		else if entity.starts_with("#x"):
			out.append(scalar(digits(entity.drop(2), 16))?)
		else if entity.starts_with("#"):
			out.append(scalar(digits(entity.drop(1), 10))?)
		else:
			return error(Error("XML: invalid data", kind: "EBADMSG"))

		out.append(tail.drop(end.get(0) + 1))

	return ok(out.build())

// The value of a character reference's digits, or none for an empty run, a sign, or any
// non-digit.
fn digits(text: String, radix: Int) Int?:
	if text.is_empty() or text.starts_with("+") or text.starts_with("-"): return none

	value := parse_int(text, radix)
	if value.is_error(): return none

	return value.get(0)

// Whether a code point is in XML 1.0's Char production, which excludes NUL, most
// controls, and U+FFFE and U+FFFF.
fn is_xml_char(code: Int) Bool:
	if code == 9 or code == 10 or code == 13: return true
	return (
		(code >= 32 and code <= 55295)
		or (code >= 57344 and code <= 65533)
		or (code >= 65536 and code <= 1114111)
	)

fn scalar(value: Int?) String!:
	if value.is_none() or not is_xml_char(value.get(0)): return error(
		Error("XML: invalid data", kind: "EBADMSG")
	)

	text := from_scalars([value.get(0)])
	if text.is_error(): return error(Error("XML: invalid data", kind: "EBADMSG"))

	return ok(text.get())

/*
Parses a document with a single root element and returns that element.
`max_depth` bounds element nesting (default 1000); deeper input is `EOVERFLOW`.
A document with several roots, text outside the root, or any syntax error is `EBADMSG`.
An XML declaration is allowed only at the start, after an optional BOM. Its encoding
name is checked for valid syntax; the String input has already been decoded.
*/
export fn parse(text: String, max_depth: Int = 1000) XmlNode!:
	if max_depth <= 0: return error(Error("XML: invalid input", kind: "EINVAL"))

	// XML's Char production applies even to discarded comments and instructions.
	for code in text.scalar_values():
		if not is_xml_char(code): return error(
			Error("XML: invalid data", kind: "EBADMSG")
		)

	// XML 1.0 section 2.11: `\r\n` and a lone `\r` reach the parser as `\n`; `&#13;` is
	// unaffected.
	normalized := if text.contains("\r"): text.replace("\r\n", "\n").replace(
		"\r",
		"\n",
	) else: text.clone()
	var reader = Reader(chars: normalized.chars(), at: 0, max_depth: max_depth)
	if reader.peek() == "\u{feff}": reader.at += 1
	reader.skip_misc(declaration_allowed: true, doctype_allowed: true)?

	root := reader.element(1)?
	reader.skip_misc()?
	if not reader.done(): return error(Error("XML: invalid data", kind: "EBADMSG"))

	return ok(root)

// Escapes `&`, `<`, `>` and carriage return for text content; a raw `\r` would read
// back as `\n`.
export fn escape_text(text: String) String:
	return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace(
		"\r",
		"&#13;",
	)

// Escapes text for a double-quoted attribute value.
export fn escape_attribute(text: String) String:
	return escape_text(text).replace("\"", "&quot;").replace("\n", "&#10;").replace(
		"\t",
		"&#9;",
	)

// Writes a node as XML. A non-empty `indent` (such as two spaces) puts each element on
// its own line, except elements holding text, which stay on one line. An element with
// no children is self-closing.
export fn stringify(node: XmlNode, indent: String = "") String:
	var out = StringBuilder()
	write(node, indent, 0, var out)
	return out.build()

fn write(node: XmlNode, indent: String, level: Int, var out: StringBuilder) Unit:
	pad := if indent.is_empty(): "" else: indent.repeat(level).get("")
	newline := if indent.is_empty(): "" else: "\n"

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

			if not indent.is_empty():
				for child in children:
					if child.tag().is_empty() and child.text() != "":
						has_text = true
						break

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
