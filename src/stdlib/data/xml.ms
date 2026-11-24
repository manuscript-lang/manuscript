import (
	parse_int from "@std/math/math.ms",
	from_scalars from "@std/string.ms",
)

// An element with fewer attributes than this checks duplicate names by scanning them.
ATTRIBUTE_SCAN_LIMIT := 16

/*
XML documents as a tree of elements, text and comments, parsed and written in Manuscript.
`parse` accepts well-formed XML 1.0 without DTD processing, and `stringify` writes a tree
back with escaping.

A DOCTYPE is read only far enough to find its end (its name, external identifier and the
extent of an internal subset) and is then dropped. Its declarations are neither checked nor
applied, an external subset is never fetched, and no entity a DTD defines is ever expanded.
Only the five predefined entities and numeric character references resolve, so any other
`&name;` is an error.

The input is text: decode UTF-16 and other encodings before parsing. Names keep their
prefix as written (`svg:rect`); namespaces are not resolved.

<!-- manuscript-example: {"mode":"fragment","given":[]} -->
```manuscript
import parse from "@std/data/xml.ms"
doc := parse("<feed><item id=\"1\">Hi &amp; bye</item></feed>")?
item := doc.find("item").get()
print(item.attribute("id").get_or("")) // "1"
print(item.text())                  // "Hi & bye"
```
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

// Returns the value of the attribute `name`, or null when it is absent or the node is
// not an element.
fn XmlNode.attribute(name: String) String?:
	match self:
		XmlElement(_, attributes, _):
			for attribute in attributes:
				if attribute.name == name: return attribute.value.clone()
			return null
		_: return null

// Returns the child nodes of an element, or an empty list. The result is an owned
// copy.
fn XmlNode.children() List[XmlNode]:
	match self:
		XmlElement(_, _, children): return children.clone()
		_: return List[XmlNode]()

// Returns all descendant text joined in document order, without comments.
fn XmlNode.text() String:
	var out = ""
	collect_text(self, out)
	return out

// Returns the first direct child element named `name`, or null. The result is an
// owned copy.
fn XmlNode.find(name: String) XmlNode?:
	match self:
		XmlElement(_, _, children):
			for child in children:
				if child.tag() == name: return child.clone()
			return null
		_: return null

// Returns every direct child element named `name`, in order.
fn XmlNode.find_all(name: String) List[XmlNode]:
	var found = List[XmlNode]()

	match self:
		XmlElement(_, _, children):
			for child in children:
				if child.tag() == name: found.append(child.clone())
		_: return found

	return found

fn collect_text(node: XmlNode, var out: String) Void:
	match node:
		XmlText(text): out += text
		XmlElement(_, _, children):
			for child in children:
				collect_text(child, out)
		_: return

// A malformed-input error at scalar index `at`, with its line, column and reason.
fn invalid_at(chars: List[String], at: Int, reason: String) Error:
	var line = 1
	var column = 1

	for index in 0..at:
		if chars.get_or(index, "") == "\n":
			line += 1
			column = 1
		else:
			column += 1

	return Error(
		f"XML {line}:{column}: {reason}",
		kind: "EBADMSG",
		details: {
			"line": line.to_string(),
			"column": column.to_string(),
			"reason": reason.clone()
		},
	)

// A cursor over the document's scalars.
type Reader:
	chars: List[String]
	// The scalar values of `chars`, so literals are matched without building strings.
	codes: List[Int]
	// The normalized document and whether it is all ASCII; then a scalar index is a
	// byte offset and a span of the document is one slice, not a string built scalar by
	// scalar.
	text: String
	ascii: Bool
	at: Int
	max_depth: Int

fn Reader.peek(offset: Int = 0) String:
	return self.chars.get_or(self.at + offset, "")

fn Reader.looking_at(literal: String) Bool:
	var k = 0

	for code in literal.scalar_values():
		if self.codes.get_or(self.at + k, -1) != code: return false

		k += 1

	return true

// The document text from scalar `start` up to `end`.
fn Reader.span(start: Int, end: Int) String:
	if self.ascii: return self.text.view(start, end).clone()

	var out = ""
	for k in start..end: out += self.chars[k]
	return out

fn Reader.done() Bool:
	return self.at >= self.chars.length()

// A malformed-input error at the cursor.
fn Reader.invalid(reason: String) Error:
	return invalid_at(self.chars, self.at, reason)

fn var Reader.skip_space() Void:
	while not self.done() and is_space(self.peek()):
		self.at += 1

// Consumes `literal` or fails.
fn var Reader.expect(literal: String) Void!:
	if not self.looking_at(literal): return error(self.invalid(f"expected `{literal}`"))

	// Every literal passed here is ASCII, so its byte length is its scalar count.
	self.at += literal.length()

// Returns the text up to `stop` and consumes it, or fails when `stop` never appears;
// `what` names the construct in that error, which points at `opened`, where it began.
fn var Reader.take_until(stop: String, what: String, opened: Int) String!:
	var wanted: List[Int] = []
	for code in stop.scalar_values(): wanted.append(code)

	start := self.at
	count := self.codes.length()
	head := wanted[0]

	while self.at < count:
		if self.codes[self.at] == head:
			var matches = true

			for k in 1..wanted.length():
				if self.codes.get_or(self.at + k, -1) != wanted[k]:
					matches = false
					break

			if matches:
				found := self.span(start, self.at)
				self.at += wanted.length()
				return ok(found)

		self.at += 1

	return error(invalid_at(self.chars, opened, f"unterminated {what}"))

// XML comments cannot contain a double hyphen or end with a hyphen.
fn var Reader.comment() String!:
	start := self.at
	self.expect("<!--")?

	text := self.take_until("-->", "comment", start)?
	if text.contains("--") or text.ends_with("-"): return error(
		invalid_at(
			self.chars,
			start,
			"a comment cannot contain `--` or end with `-`",
		)
	)

	return ok(text)

fn var Reader.name() String!:
	start := self.at
	count := self.codes.length()
	while self.at < count and is_name_char(self.codes[self.at], self.at == start): self.at += 1
	if self.at == start: return error(self.invalid("expected a name"))

	return ok(self.span(start, self.at))

// The reserved target `xml` belongs to a declaration, never a processing
// instruction.
fn var Reader.instruction() Void!:
	start := self.at
	self.expect("<?")?

	target := self.name()?
	if target.length() == 3 and target.lower() == "xml": return error(
		self.invalid("the target `xml` is reserved for the XML declaration")
	)
	if not self.looking_at("?>") and not is_space(self.peek()): return error(
		self.invalid("expected whitespace or `?>` after the instruction target")
	)

	_data := self.take_until("?>", "processing instruction", start)?

// Declaration values are literals, not entity-decoded XML attribute values.
fn var Reader.declaration_attribute() XmlAttribute!:
	name := self.name()?
	self.skip_space()
	self.expect("=")?
	self.skip_space()

	quote := self.peek().clone()
	if quote != "\"" and quote != "'": return error(
		self.invalid("expected a quoted value")
	)

	self.at += 1
	return ok(XmlAttribute(name, self.take_until(quote, "quoted value", self.at - 1)?))

// XMLDecl: mandatory version, optional encoding, optional standalone, in that
// order.
fn var Reader.declaration() Void!:
	self.expect("<?xml")?
	if not is_space(self.peek()): return error(
		self.invalid("expected whitespace after `<?xml`")
	)

	self.skip_space()

	version_at := self.at
	version := self.declaration_attribute()?
	if version.name != "version" or not is_version(version.value): return error(
		invalid_at(
			self.chars,
			version_at,
			"the XML declaration must start with a 1.x `version`",
		)
	)

	var encoding_seen = false
	var standalone_seen = false

	while true:
		before := self.at
		self.skip_space()

		if self.looking_at("?>"):
			self.at += 2
			return ok()

		if self.at == before: return error(self.invalid("expected whitespace or `?>`"))

		attribute_at := self.at
		attribute := self.declaration_attribute()?

		if (attribute.name == "encoding" and not encoding_seen and not standalone_seen):
			if not is_encoding_name(attribute.value): return error(
				invalid_at(
					self.chars,
					attribute_at,
					"invalid encoding name",
				)
			)

			encoding_seen = true
		else if attribute.name == "standalone" and not standalone_seen:
			if attribute.value != "yes" and attribute.value != "no": return error(
				invalid_at(
					self.chars,
					attribute_at,
					"standalone must be `yes` or `no`",
				)
			)

			standalone_seen = true
		else:
			return error(
				invalid_at(
					self.chars,
					attribute_at,
					f"unexpected `{attribute.name}` in the XML declaration",
				)
			)

// Skips a quoted literal; its contents never delimit markup.
fn var Reader.quoted(public_id: Bool = false) Void!:
	quote := self.peek().clone()
	if quote != "\"" and quote != "'": return error(
		self.invalid("expected a quoted literal")
	)

	self.at += 1

	start := self.at
	text := self.take_until(quote, "quoted literal", start - 1)?

	if public_id:
		for c in text.chars():
			code := c.scalar_at(0)
			alphanumeric := (
				(code >= 0x41 and code <= 0x5a)
				or (code >= 0x61 and code <= 0x7a)
				or (code >= 0x30 and code <= 0x39)
			)
			if not alphanumeric and not " \r\n-'()+,./:=?;!*#@$_%".contains(c):
				return error(
					invalid_at(
						self.chars,
						start,
						"invalid character in the public identifier",
					)
				)

// Requires at least one whitespace scalar.
fn var Reader.require_space() Void!:
	before := self.at
	self.skip_space()
	if self.at == before: return error(self.invalid("expected whitespace"))

// XML 1.0 section 2.8 `intSubset`: declarations, comments, instructions and
// parameter references, with quoted spans skipped so `]` and `>` inside them are
// plain text.
fn var Reader.internal_subset() Void!:
	while true:
		self.skip_space()

		if self.looking_at("]"):
			self.at += 1
			return ok()

		if self.looking_at("<!--"):
			_comment := self.comment()?
		else if self.looking_at("<?"):
			self.instruction()?
		else if self.looking_at("<!"):
			self.at += 2

			while not self.looking_at(">"):
				if self.done(): return error(
					self.invalid(
						"unterminated declaration in the DOCTYPE"
					)
				)

				if self.peek() == "\"" or self.peek() == "'":
					self.quoted()?
				else:
					self.at += 1

			self.at += 1
		else if self.looking_at("%"):
			_reference := self.take_until(";", "parameter entity reference", self.at)?
		else:
			return error(
				self.invalid(
					"unexpected content in the DOCTYPE internal subset"
				)
			)

// XML 1.0 section 2.8 `doctypedecl`: name, optional external identifier, optional
// internal subset.
fn var Reader.doctype() Void!:
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
) Void!:
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

	return ok()

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
		here := self.codes.get_or(self.at, -1)

		if here == 0x2f and self.codes.get_or(self.at + 1, -1) == 0x3e:
			self.at += 2
			return ok(XmlElement(name, attributes, List[XmlNode]()))

		if here == 0x3e:
			self.at += 1
			break

		// Attributes are separated by whitespace, so `a="1"b="2"` is malformed.
		if not separated: return error(
			self.invalid("attributes must be separated by whitespace")
		)

		name_at := self.at
		attribute_name := self.name()?
		self.skip_space()
		self.expect("=")?
		self.skip_space()

		quote := self.peek().clone()
		if quote != "\"" and quote != "'": return error(
			self.invalid("expected a quoted attribute value")
		)

		self.at += 1

		value_at := self.at
		source := self.take_until(quote, "attribute value", value_at - 1)?
		if source.contains("<"): return error(
			invalid_at(
				self.chars,
				value_at,
				"`<` is not allowed in an attribute value",
			)
		)

		// XML 1.0 section 3.3.3: literal tabs and line ends in a value become
		// spaces; references are decoded afterwards.
		raw := source.replace("\n", " ").replace("\t", " ")

		// A short list is scanned; a long one moves to a set so names are checked
		// in constant time.
		if attributes.length() < ATTRIBUTE_SCAN_LIMIT:
			for existing in attributes:
				if existing.name == attribute_name: return error(
					invalid_at(
						self.chars,
						name_at,
						f"duplicate attribute `{attribute_name}`",
					)
				)
		else:
			if seen.is_empty():
				for existing in attributes:
					seen.add(existing.name.clone())
			if seen.contains(attribute_name): return error(
				invalid_at(
					self.chars,
					name_at,
					f"duplicate attribute `{attribute_name}`",
				)
			)

			seen.add(attribute_name.clone())

		attributes.append(
			XmlAttribute(
				name: attribute_name,
				value: decode(raw, self.chars, value_at)?,
			)
		)

	var children = List[XmlNode]()

	while true:
		if self.done(): return error(
			self.invalid(f"the element `{name}` is never closed")
		)

		// The first two scalars pick the construct, so the literals are tested only
		// when they could match.
		opens := self.codes.get_or(self.at, -1) == 0x3c
		next := self.codes.get_or(self.at + 1, -1)

		if opens and next == 0x2f:
			self.at += 2

			closing_at := self.at
			closing := self.name()?
			if closing != name: return error(
				invalid_at(
					self.chars,
					closing_at,
					f"closing tag `{closing}` does not match `{name}`",
				)
			)

			self.skip_space()
			self.expect(">")?
			return ok(XmlElement(name, attributes, children))

		if opens and next == 0x21 and self.looking_at("<!--"):
			children.append(XmlComment(self.comment()?))
		else if opens and next == 0x21 and self.looking_at("<![CDATA["):
			self.at += 9
			children.append(
				XmlText(
					self.take_until(
						"]]>",
						"CDATA section",
						self.at - 9,
					)?
				)
			)
		else if opens and next == 0x3f:
			self.instruction()?
		else if opens:
			children.append(self.element(depth + 1)?)
		else:
			text_at := self.at
			while self.at < self.codes.length() and self.codes[self.at] != 0x3c: self.at += 1

			raw := self.span(text_at, self.at)
			if raw.contains("]]>"): return error(
				invalid_at(
					self.chars,
					text_at,
					"`]]>` is not allowed in text",
				)
			)

			children.append(XmlText(decode(raw, self.chars, text_at)?))

fn is_space(c: String) Bool:
	return c == " " or c == "\t" or c == "\n" or c == "\r"

// XML 1.0 processes other 1.x versions using the same grammar (section 2.8).
fn is_version(text: String) Bool:
	if not text.starts_with("1.") or text.length() <= 2: return false

	for code in text.view(2, text.length()).scalar_values():
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
fn is_name_char(code: Int, first: Bool) Bool:
	// ASCII first: letters, `_` and `:` start a name, digits, `-` and `.` continue it.
	if code < 0x80:
		if (code >= 0x61 and code <= 0x7a) or (code >= 0x41 and code <= 0x5a): return true
		if code == 0x5f or code == 0x3a: return true
		if first: return false

		return code == 0x2d or code == 0x2e or (code >= 0x30 and code <= 0x39)

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
fn decode(text: String, chars: List[String], start: Int) String!:
	if not text.contains("&"): return ok(text.clone())

	var out = ""

	// Every piece after the first starts right after an `&`, so each is scanned once.
	pieces := text.split("&")
	out += pieces[0]

	var index = 1

	// The scalar index in the document of the `&` that starts the current piece.
	var ampersand = start + pieces[0].scalar_length()

	while index < pieces.length():
		tail := pieces[index]
		index += 1

		here := ampersand
		ampersand += 1 + tail.scalar_length()

		end := tail.index_of(";")
		if end == null: return error(
			invalid_at(chars, here, "an entity reference must end with `;`")
		)

		entity := tail.view(0, end)

		if entity == "lt": out += "<"
		else if entity == "gt": out += ">"
		else if entity == "amp": out += "&"
		else if entity == "quot": out += "\""
		else if entity == "apos": out += "'"
		else if entity.starts_with("#x"):
			out += scalar(chars, here, digits(entity.view(2, entity.length()), 16))?
		else if entity.starts_with("#"):
			out += scalar(chars, here, digits(entity.view(1, entity.length()), 10))?
		else:
			return error(invalid_at(chars, here, f"unknown entity `&{entity};`"))

		out += tail.view((end) + 1, tail.length())

	return ok(out)

// The value of a character reference's digits, or null for an empty run, a sign, or any
// non-digit.
fn digits(text: String, radix: Int) Int?:
	if text.is_empty() or text.starts_with("+") or text.starts_with("-"): return null

	value := parse_int(text, radix)
	if value.is_error(): return null

	return value.get_or(0)

// Whether a code point is in XML 1.0's Char production, which excludes NUL, most
// controls, and U+FFFE and U+FFFF.
fn is_xml_char(code: Int) Bool:
	if code == 9 or code == 10 or code == 13: return true
	return (
		(code >= 32 and code <= 55295)
		or (code >= 57344 and code <= 65533)
		or (code >= 65536 and code <= 1114111)
	)

fn scalar(chars: List[String], at: Int, value: Int?) String!:
	if (value == null) or not is_xml_char(value): return error(
		invalid_at(chars, at, "invalid character reference")
	)

	text := from_scalars([(value)])
	if text.is_error(): return error(
		invalid_at(chars, at, "invalid character reference")
	)

	return ok(text.get())

/*
Parses a document with a single root element and returns that element.
`max_depth` bounds element nesting (default 1000); deeper input returns `EOVERFLOW`, and a
`max_depth` of zero or less returns `EINVAL`.
A document with several roots, text outside the root, or any syntax error returns `EBADMSG`.
Its message reads `XML <line>:<column>: <reason>`, and `details` holds `line`, `column` and
`reason`, counted in scalars after line ends are normalized.
An XML declaration is allowed only at the start, after an optional BOM. Its encoding
name is checked for valid syntax; the String input has already been decoded.
*/
export fn parse(text: String, max_depth: Int = 1000) XmlNode!:
	if max_depth <= 0: return error(Error("XML: invalid input", kind: "EINVAL"))

	// XML 1.0 section 2.11: `\r\n` and a lone `\r` reach the parser as `\n`; `&#13;` is
	// unaffected.
	normalized := if text.contains("\r"): text.replace("\r\n", "\n").replace(
		"\r",
		"\n",
	) else: text.clone()
	var chars = normalized.chars().clone()
	var codes: List[Int] = []
	var ascii = true

	for code in normalized.scalar_values():
		codes.append(code)
		if code >= 0x80: ascii = false

	if codes.get_or(0, 0) == 0xfeff:
		chars.remove(0)
		codes.remove(0)

	// XML's Char production applies even to discarded comments and instructions.
	for index in 0..codes.length():
		code := codes[index]
		if not is_xml_char(code): return error(
			invalid_at(
				chars,
				index,
				f"invalid character U+{code.to_hex().pad_start(4, "0").upper()}",
			)
		)

	var reader = Reader(
		chars: chars,
		codes: codes,
		text: normalized,
		ascii: ascii,
		at: 0,
		max_depth: max_depth,
	)
	reader.skip_misc(declaration_allowed: true, doctype_allowed: true)?
	if not reader.looking_at("<"): return error(
		reader.invalid("expected the root element")
	)

	root := reader.element(1)?
	reader.skip_misc()?
	if not reader.done(): return error(
		reader.invalid("unexpected content after the root element")
	)

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
	var out = ""
	write(node, indent, 0, out)
	return out

fn write(node: XmlNode, indent: String, level: Int, var out: String) Void:
	pad := if indent.is_empty(): "" else: indent.repeat(level)
	newline := if indent.is_empty(): "" else: "\n"

	match node:
		XmlText(text): out += escape_text(text)
		XmlComment(text): out += f"{pad}<!--{text}-->{newline}"
		XmlElement(name, attributes, children):
			out += f"{pad}<{name}"
			for attribute in attributes:
				out += f" {attribute.name}=\"{escape_attribute(attribute.value)}\""

			if children.is_empty():
				out += f"/>{newline}"
				return

			var has_text = false

			if not indent.is_empty():
				for child in children:
					if child.tag().is_empty() and child.text() != "":
						has_text = true
						break

			if has_text or indent.is_empty():
				out += ">"
				for child in children:
					write(child, "", 0, out)
				out += f"</{name}>{newline}"
			else:
				out += f">{newline}"
				for child in children:
					write(child, indent, level + 1, out)
				out += f"{pad}</{name}>{newline}"
