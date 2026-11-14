import (
	Bytes from "@std/bytes.ms",
	StringBuilder from "@std/string_builder.ms",

	msstd_html_decode,
	msstd_html_escape,
	msstd_html_unescape from "@std/internal/html.ms",
)

// Bounds for HTML input bytes, tree depth, and node count.
// Fields set to none add no budget. The defaults are depth 10,000 and 1,000,000 nodes.
export type HtmlOptions:
	// Maximum UTF-8 input bytes before parsing; none adds no input-size budget.
	max_bytes: Int? = none
	// Maximum normalized node depth; the document is depth zero and direct children
	// depth one.
	max_depth: Int? = 10000
	// Maximum returned nodes, including document/text/comment/doctype and implied
	// element nodes.
	max_nodes: Int? = 1000000

// An HTML attribute, including its namespace and decoded value.
export type HtmlAttribute:
	// Local attribute name after native HTML parsing and normalization.
	name: String
	// Attribute namespace prefix, or empty text for an unqualified attribute.
	namespace: String
	// Decoded attribute contents, with character references resolved.
	value: String

// A parsed HTML document tree with document, element, text, comment, and doctype nodes.
export enum HtmlNode:
	// Root document node, including any elements implied by HTML tree normalization.
	Document(
		// Direct child nodes in normalized document order.
		children: List[HtmlNode]
	)
	// An element with normalized attributes and its ordered child nodes.
	Element(
		// Local element tag name produced by the HTML parser.
		tag: String,
		// Element namespace, such as svg/math, or empty text for ordinary HTML.
		namespace: String,
		// Attributes in parser order, with decoded values and namespace information.
		attributes: List[HtmlAttribute],
		// Direct child nodes in normalized tree order; mutable list storage is
		// retained.
		children: List[HtmlNode]
	)
	// Text node contents after HTML entity decoding and tree normalization.
	Text(
		// Unicode text belonging to this node, without surrounding markup.
		text: String
	)
	// An HTML comment retained as a node rather than element text.
	Comment(
		// Comment contents without the opening and closing comment delimiters.
		text: String
	)
	// A document-type declaration retained from the parsed HTML.
	Doctype(
		// Doctype name supplied by the native HTML parser.
		name: String,
		// Public identifier, or empty text when no public identifier is present.
		public_id: String,
		// System identifier, or empty text when no system identifier is present.
		system_id: String
	)

// Escapes text for insertion into an HTML text or quoted attribute context.
export fn escape(text: String) String:
	return msstd_html_escape(text)

// Decodes HTML5 named and numeric character references in text context, once.
// Recognized references can omit semicolons; unrecognized text remains literal.
// Does not parse markup or normalize text; invalid numeric scalars become U+FFFD.
export fn unescape(text: String) String:
	return msstd_html_unescape(text)

// ---- parser state ----

// Token types.
T_ERROR := 0
T_TEXT := 1
T_START := 2
T_END := 3
T_SELF_CLOSING := 4
T_COMMENT := 5
T_DOCTYPE := 6
// Node kinds. Scope markers sit in the active formatting list and are never in the
// tree.
K_DOCUMENT := 0
K_ELEMENT := 1
K_TEXT := 2
K_COMMENT := 3
K_DOCTYPE := 4
K_MARKER := 5
// Namespaces: 0 is HTML.
NS_HTML := 0
NS_MATH := 1
NS_SVG := 2
// Raw-text elements the tokenizer reads as text up to the matching end tag.
RAW_NONE := 0
RAW_IFRAME := 1
RAW_NOEMBED := 2
RAW_NOFRAMES := 3
RAW_NOSCRIPT := 4
RAW_PLAINTEXT := 5
RAW_SCRIPT := 6
RAW_STYLE := 7
RAW_TEXTAREA := 8
RAW_TITLE := 9
RAW_XMP := 10
// Scopes for element searches.
SCOPE_DEFAULT := 0
SCOPE_LIST_ITEM := 1
SCOPE_BUTTON := 2
SCOPE_TABLE := 3
SCOPE_TABLE_ROW := 4
SCOPE_TABLE_BODY := 5
SCOPE_SELECT := 6
// Insertion modes.
IM_INITIAL := 0
IM_BEFORE_HTML := 1
IM_BEFORE_HEAD := 2
IM_IN_HEAD := 3
IM_AFTER_HEAD := 4
IM_IN_BODY := 5
IM_TEXT := 6
IM_IN_TABLE := 7
IM_IN_CAPTION := 8
IM_IN_COLUMN_GROUP := 9
IM_IN_TABLE_BODY := 10
IM_IN_ROW := 11
IM_IN_CELL := 12
IM_IN_SELECT := 13
IM_IN_SELECT_IN_TABLE := 14
IM_IN_TEMPLATE := 15
IM_AFTER_BODY := 16
IM_IN_FRAMESET := 17
IM_AFTER_FRAMESET := 18
IM_AFTER_AFTER_BODY := 19
IM_AFTER_AFTER_FRAMESET := 20
IM_IGNORE_REMAINING := 21
// Script data tokenizer states.
SC_DATA := 0
SC_LESS_THAN := 1
SC_END_TAG_OPEN := 2
SC_ESCAPE_START := 3
SC_ESCAPE_START_DASH := 4
SC_ESCAPED := 5
SC_ESCAPED_DASH := 6
SC_ESCAPED_DASH_DASH := 7
SC_ESCAPED_LESS_THAN := 8
SC_ESCAPED_END_TAG_OPEN := 9
SC_DOUBLE_ESCAPE_START := 10
SC_DOUBLE_ESCAPED := 11
SC_DOUBLE_ESCAPED_DASH := 12
SC_DOUBLE_ESCAPED_DASH_DASH := 13
SC_DOUBLE_ESCAPED_LESS_THAN := 14
SC_DOUBLE_ESCAPE_END := 15
// In-body start-tag rules, from `body_start_class`.
S_HTML := 1
S_HEAD_LIKE := 2
S_BODY := 3
S_FRAMESET := 4
S_BLOCK := 5
S_HEADING := 6
S_PRE := 7
S_FORM := 8
S_LI := 9
S_DD_DT := 10
S_PLAINTEXT := 11
S_BUTTON := 12
S_ANCHOR := 13
S_FORMATTING := 14
S_NOBR := 15
S_APPLET := 16
S_TABLE := 17
S_VOID_REOPEN := 18
S_VOID := 19
S_HR := 20
S_IMAGE := 21
S_TEXTAREA := 22
S_XMP := 23
S_IFRAME := 24
S_NOEMBED := 25
S_NOSCRIPT := 26
S_SELECT := 27
S_OPTION := 28
S_RUBY_BASE := 29
S_RUBY_TEXT := 30
S_FOREIGN := 31
S_TABLE_PART := 32
// In-body end-tag rules, from `body_end_class`.
E_BODY := 1
E_HTML := 2
E_BLOCK := 3
E_FORM := 4
E_P := 5
E_LI := 6
E_DD_DT := 7
E_HEADING := 8
E_FORMATTING := 9
E_APPLET := 10
E_BR := 11
E_TEMPLATE := 12

// The open elements, the active formatting elements and the tree are flat arrays
// indexed by node id: node 0 is the formatting-list marker and node 1 the document. A
// node's name is its atom (see the generated tables), or `data` when the tag is not a
// known atom.
type Parser:
	src: Bytes
	size: Int
	max_open: Int
	exceeded: Bool = false
	// Tokenizer state.
	eof: Bool = false
	raw_start: Int = 0
	raw_end: Int = 0
	data_start: Int = 0
	data_end: Int = 0
	tt: Int = 0
	pk_s: Int = 0
	pk_e: Int = 0
	pv_s: Int = 0
	pv_e: Int = 0
	attr_n: Int = 0
	attr_ks: List[Int] = []
	attr_ke: List[Int] = []
	attr_vs: List[Int] = []
	attr_ve: List[Int] = []
	raw_tag: Int = 0
	raw_name: Bytes = Bytes(values: [])
	text_is_raw: Bool = false
	convert_nul: Bool = false
	allow_cdata: Bool = false
	// The current token. A tag's name is `tok_atom`, or `tok_data` when it has no atom;
	// attributes are the first `tok_n` entries of the three lists.
	tok_ty: Int = 0
	tok_atom: Int = 0
	tok_data: String = ""
	tok_n: Int = 0
	tok_keys: List[String] = []
	tok_vals: List[String] = []
	tok_nss: List[String] = []
	has_self_closing: Bool = false
	// The tree.
	kind: List[Int] = [K_MARKER, K_DOCUMENT]
	atom: List[Int] = [0, 0]
	data: List[String] = ["", ""]
	ns: List[Int] = [0, 0]
	parent: List[Int] = [-1, -1]
	first: List[Int] = [-1, -1]
	last: List[Int] = [-1, -1]
	prev: List[Int] = [-1, -1]
	next: List[Int] = [-1, -1]
	attr_start: List[Int] = [0, 0]
	attr_count: List[Int] = [0, 0]
	akey: List[String] = []
	aval: List[String] = []
	ans: List[String] = []
	// Open elements, with the nearest `p` and the nearest button-scope boundary at or
	// below each entry (index plus one), so "is a `p` open in button scope" needs no
	// stack walk.
	oe: List[Int] = []
	oe_p: List[Int] = []
	oe_stop: List[Int] = []
	afe: List[Int] = []
	head: Int = -1
	form: Int = -1
	frameset_ok: Bool = true
	template_stack: List[Int] = []
	im: Int = 0
	original_im: Int = -1
	foster_parenting: Bool = false
	quirks: Bool = false

fn var Parser.read_byte() Int:
	if self.raw_end >= self.size:
		self.eof = true
		return 0

	x := self.src.get(self.raw_end).to_int()
	self.raw_end += 1
	return x

fn var Parser.skip_white_space() Unit:
	if self.eof: return

	while true:
		c := self.read_byte()
		if self.eof: return

		if not is_space(c):
			self.raw_end -= 1
			return

fn var Parser.set_raw_tag(tag: Int) Unit:
	self.raw_tag = tag

	match tag:
		1: self.raw_name = "iframe".to_bytes()
		2: self.raw_name = "noembed".to_bytes()
		3: self.raw_name = "noframes".to_bytes()
		4: self.raw_name = "noscript".to_bytes()
		5: self.raw_name = "plaintext".to_bytes()
		6: self.raw_name = "script".to_bytes()
		7: self.raw_name = "style".to_bytes()
		8: self.raw_name = "textarea".to_bytes()
		9: self.raw_name = "title".to_bytes()
		10: self.raw_name = "xmp".to_bytes()
		_: self.raw_name = Bytes(values: [])

fn var Parser.read_raw_or_rcdata() Unit:
	if self.raw_tag == RAW_SCRIPT:
		self.read_script()
		self.text_is_raw = true
		self.raw_tag = RAW_NONE
		return

	while true:
		c := self.read_byte()
		if self.eof: break
		if c != 60: continue

		c2 := self.read_byte()
		if self.eof: break

		if c2 != 47:
			self.raw_end -= 1
			continue

		if self.read_raw_end_tag() or self.eof: break

	self.data_end = self.raw_end
	self.text_is_raw = self.raw_tag != RAW_TEXTAREA and self.raw_tag != RAW_TITLE
	self.raw_tag = RAW_NONE

fn var Parser.read_raw_end_tag() Bool:
	length := self.raw_name.length()

	for i in 0..length:
		c := self.read_byte()
		if self.eof: return false

		t := self.raw_name.get(i).to_int()

		if c != t and c != t - 32:
			self.raw_end -= 1
			return false

	c := self.read_byte()
	if self.eof: return false

	if is_space(c) or c == 47 or c == 62:
		self.raw_end -= 3 + length
		return true

	self.raw_end -= 1
	return false

fn var Parser.read_script() Unit:
	var st = SC_DATA

	while true:
		if st == SC_DATA:
			c := self.read_byte()
			if self.eof: break

			if c == 60:
				st = SC_LESS_THAN
		else if st == SC_LESS_THAN:
			c := self.read_byte()
			if self.eof: break

			if c == 47:
				st = SC_END_TAG_OPEN
			else if c == 33:
				st = SC_ESCAPE_START
			else:
				self.raw_end -= 1
				st = SC_DATA
		else if st == SC_END_TAG_OPEN:
			if self.read_raw_end_tag() or self.eof: break

			st = SC_DATA
		else if st == SC_ESCAPE_START:
			c := self.read_byte()
			if self.eof: break

			if c == 45:
				st = SC_ESCAPE_START_DASH
			else:
				self.raw_end -= 1
				st = SC_DATA
		else if st == SC_ESCAPE_START_DASH:
			c := self.read_byte()
			if self.eof: break

			if c == 45:
				st = SC_ESCAPED_DASH_DASH
			else:
				self.raw_end -= 1
				st = SC_DATA
		else if st == SC_ESCAPED:
			c := self.read_byte()
			if self.eof: break

			if c == 45:
				st = SC_ESCAPED_DASH
			else if c == 60:
				st = SC_ESCAPED_LESS_THAN
		else if st == SC_ESCAPED_DASH:
			c := self.read_byte()
			if self.eof: break

			if c == 45:
				st = SC_ESCAPED_DASH_DASH
			else if c == 60:
				st = SC_ESCAPED_LESS_THAN
			else:
				st = SC_ESCAPED
		else if st == SC_ESCAPED_DASH_DASH:
			c := self.read_byte()
			if self.eof: break

			if c == 45:
				st = SC_ESCAPED_DASH_DASH
			else if c == 60:
				st = SC_ESCAPED_LESS_THAN
			else if c == 62:
				st = SC_DATA
			else:
				st = SC_ESCAPED
		else if st == SC_ESCAPED_LESS_THAN:
			c := self.read_byte()
			if self.eof: break

			if c == 47:
				st = SC_ESCAPED_END_TAG_OPEN
			else if is_alpha(c):
				st = SC_DOUBLE_ESCAPE_START
			else:
				self.raw_end -= 1
				st = SC_DATA
		else if st == SC_ESCAPED_END_TAG_OPEN:
			if self.read_raw_end_tag() or self.eof: break

			st = SC_ESCAPED
		else if st == SC_DOUBLE_ESCAPE_START:
			self.raw_end -= 1

			var mismatch = false
			script := "script".to_bytes()

			for i in 0..6:
				c := self.read_byte()

				if self.eof:
					self.data_end = self.raw_end
					return

				t := script.get(i).to_int()

				if c != t and c != t - 32:
					self.raw_end -= 1
					mismatch = true
					break

			if mismatch:
				st = SC_ESCAPED
			else:
				c := self.read_byte()
				if self.eof: break

				if is_space(c) or c == 47 or c == 62:
					st = SC_DOUBLE_ESCAPED
				else:
					self.raw_end -= 1
					st = SC_ESCAPED
		else if st == SC_DOUBLE_ESCAPED:
			c := self.read_byte()
			if self.eof: break

			if c == 45:
				st = SC_DOUBLE_ESCAPED_DASH
			else if c == 60:
				st = SC_DOUBLE_ESCAPED_LESS_THAN
		else if st == SC_DOUBLE_ESCAPED_DASH:
			c := self.read_byte()
			if self.eof: break

			if c == 45:
				st = SC_DOUBLE_ESCAPED_DASH_DASH
			else if c == 60:
				st = SC_DOUBLE_ESCAPED_LESS_THAN
			else:
				st = SC_DOUBLE_ESCAPED
		else if st == SC_DOUBLE_ESCAPED_DASH_DASH:
			c := self.read_byte()
			if self.eof: break

			if c == 45:
				st = SC_DOUBLE_ESCAPED_DASH_DASH
			else if c == 60:
				st = SC_DOUBLE_ESCAPED_LESS_THAN
			else if c == 62:
				st = SC_DATA
			else:
				st = SC_DOUBLE_ESCAPED
		else if st == SC_DOUBLE_ESCAPED_LESS_THAN:
			c := self.read_byte()
			if self.eof: break

			if c == 47:
				st = SC_DOUBLE_ESCAPE_END
			else:
				self.raw_end -= 1
				st = SC_DOUBLE_ESCAPED
		else:
			// SC_DOUBLE_ESCAPE_END
			if self.read_raw_end_tag():
				self.raw_end += 9
				st = SC_ESCAPED
			else if self.eof:
				break
			else:
				st = SC_DOUBLE_ESCAPED

	self.data_end = self.raw_end

fn var Parser.read_comment() Unit:
	self.data_start = self.raw_end

	var dash_count = 0
	var beginning = true

	while true:
		var c = self.read_byte()

		if self.eof:
			self.data_end = self.abrupt_comment_data_end()
			break

		if c == 45:
			dash_count += 1
			continue

		if c == 62:
			if dash_count >= 2 or beginning:
				self.data_end = self.raw_end - 3
				break
		else if c == 33 and dash_count >= 2:
			c = self.read_byte()

			if self.eof:
				self.data_end = self.abrupt_comment_data_end()
				break
			else if c == 62:
				self.data_end = self.raw_end - 4
				break
			else if c == 45:
				dash_count = 1
				beginning = false
				continue

		dash_count = 0
		beginning = false

	if self.data_end < self.data_start:
		self.data_end = self.data_start

fn Parser.abrupt_comment_data_end() Int:
	length := self.raw_end - self.raw_start

	if length >= 4:
		// The raw token without its first four bytes ends the way an abrupt comment
		// does.
		last := self.byte_at(self.raw_end - 1)
		prior := self.byte_at(self.raw_end - 2)
		before := self.byte_at(self.raw_end - 3)
		body := length - 4
		if body >= 3 and before == 45 and prior == 45 and last == 33: return (
			self.raw_end
			- 3
		)
		if body >= 2 and prior == 45 and last == 45: return self.raw_end - 2
		if body >= 1 and last == 45: return self.raw_end - 1

	return self.raw_end

fn Parser.byte_at(pos: Int) Int:
	if pos < 0 or pos >= self.size: return -1
	return self.src.get(pos).to_int()

fn var Parser.read_until_close_angle() Unit:
	self.data_start = self.raw_end

	idx := self.src.index_of_byte(62, self.raw_end)

	if idx.is_none():
		self.raw_end = self.size
		self.eof = true
		self.data_end = self.raw_end
		return

	self.raw_end = idx.get(0) + 1
	self.data_end = self.raw_end - 1

fn var Parser.read_markup_declaration() Int:
	self.data_start = self.raw_end

	var first = 0
	var second = 0
	first = self.read_byte()

	if self.eof:
		self.data_end = self.raw_end
		return T_COMMENT

	second = self.read_byte()

	if self.eof:
		self.data_end = self.raw_end
		return T_COMMENT

	if first == 45 and second == 45:
		self.read_comment()
		return T_COMMENT

	self.raw_end -= 2
	if self.read_doctype(): return T_DOCTYPE

	if self.allow_cdata and self.read_cdata():
		self.convert_nul = true
		return T_TEXT

	self.read_until_close_angle()
	return T_COMMENT

fn var Parser.read_doctype() Bool:
	word := "DOCTYPE".to_bytes()

	for i in 0..7:
		c := self.read_byte()

		if self.eof:
			self.data_end = self.raw_end
			return false

		s := word.get(i).to_int()

		if c != s and c != s + 32:
			self.raw_end = self.data_start
			return false

	self.skip_white_space()

	if self.eof:
		self.data_start = self.raw_end
		self.data_end = self.raw_end
		return true

	self.read_until_close_angle()
	return true

fn var Parser.read_cdata() Bool:
	word := "[CDATA[".to_bytes()

	for i in 0..7:
		c := self.read_byte()

		if self.eof:
			self.data_end = self.raw_end
			return false

		if c != word.get(i).to_int():
			self.raw_end = self.data_start
			return false

	self.data_start = self.raw_end

	var brackets = 0

	while true:
		c := self.read_byte()

		if self.eof:
			self.data_end = self.raw_end
			return true

		if c == 93:
			brackets += 1
		else if c == 62:
			if brackets >= 2:
				self.data_end = self.raw_end - 3
				return true

			brackets = 0
		else:
			brackets = 0

	return true

// The raw-text element whose name is the current tag name, or `RAW_NONE`.
fn Parser.raw_text_tag() Int:
	start := self.data_start
	length := self.data_end - start
	c := lower_byte(self.byte_at(start))
	if c == 105 and self.name_is(start, length, "iframe"): return RAW_IFRAME

	if c == 110:
		if self.name_is(start, length, "noembed"): return RAW_NOEMBED
		if self.name_is(start, length, "noframes"): return RAW_NOFRAMES
		if self.name_is(start, length, "noscript"): return RAW_NOSCRIPT

	if c == 112 and self.name_is(start, length, "plaintext"): return RAW_PLAINTEXT

	if c == 115:
		if self.name_is(start, length, "script"): return RAW_SCRIPT
		if self.name_is(start, length, "style"): return RAW_STYLE

	if c == 116:
		if self.name_is(start, length, "textarea"): return RAW_TEXTAREA
		if self.name_is(start, length, "title"): return RAW_TITLE

	if c == 120 and self.name_is(start, length, "xmp"): return RAW_XMP

	return RAW_NONE

// Whether `length` bytes at `start` equal the lower-case `word` ignoring ASCII case.
fn Parser.name_is(start: Int, length: Int, word: String) Bool:
	if length != word.byte_length(): return false
	return bytes_equal_fold(self.src, start, word.to_bytes())

fn var Parser.read_start_tag() Int:
	self.read_tag(true)
	if self.eof: return T_ERROR

	raw := self.raw_text_tag()
	if raw != RAW_NONE: self.set_raw_tag(raw)

	n := self.attr_n
	if self.byte_at(self.raw_end - 2) == 47:
		if n == 0 or self.raw_end - 2 != self.attr_ve[n - 1] - 1: return T_SELF_CLOSING
	return T_START

// Records the pending attribute spans as the next attribute of the tag.
fn var Parser.push_attr() Unit:
	n := self.attr_n

	if n < self.attr_ks.length():
		self.attr_ks[n] = self.pk_s
		self.attr_ke[n] = self.pk_e
		self.attr_vs[n] = self.pv_s
		self.attr_ve[n] = self.pv_e
	else:
		self.attr_ks.append(self.pk_s)
		self.attr_ke.append(self.pk_e)
		self.attr_vs.append(self.pv_s)
		self.attr_ve.append(self.pv_e)

	self.attr_n = n + 1

fn var Parser.read_tag(save_attr: Bool) Unit:
	self.attr_n = 0
	self.read_tag_name()
	self.skip_white_space()
	if self.eof: return

	while true:
		c := self.read_byte()
		if self.eof or c == 62: break

		self.raw_end -= 1
		self.read_tag_attr_key()
		self.read_tag_attr_val()
		if save_attr and self.pk_s != self.pk_e: self.push_attr()
		self.skip_white_space()
		if self.eof: break

fn var Parser.read_tag_name() Unit:
	self.data_start = self.raw_end - 1

	while true:
		c := self.read_byte()

		if self.eof:
			self.data_end = self.raw_end
			return

		if is_space(c):
			self.data_end = self.raw_end - 1
			return

		if c == 47 or c == 62:
			self.raw_end -= 1
			self.data_end = self.raw_end
			return

fn var Parser.read_tag_attr_key() Unit:
	self.pk_s = self.raw_end

	while true:
		c := self.read_byte()

		if self.eof:
			self.pk_e = self.raw_end
			return

		if c == 61 and self.pk_s + 1 == self.raw_end: continue

		if c == 61 or is_space(c) or c == 47 or c == 62:
			self.raw_end -= 1
			self.pk_e = self.raw_end
			return

fn var Parser.read_tag_attr_val() Unit:
	self.pv_s = self.raw_end
	self.pv_e = self.raw_end
	self.skip_white_space()
	if self.eof: return

	c := self.read_byte()
	if self.eof: return
	if c == 47: return

	if c != 61:
		self.raw_end -= 1
		return

	self.skip_white_space()
	if self.eof: return

	quote := self.read_byte()
	if self.eof: return

	if quote == 62:
		self.raw_end -= 1
	else if quote == 39 or quote == 34:
		self.pv_s = self.raw_end

		var idx: Int? = none

		if quote == 39:
			idx = self.src.index_of_byte(39, self.raw_end)
		else:
			idx = self.src.index_of_byte(34, self.raw_end)

		if idx.is_none():
			self.raw_end = self.size
			self.eof = true
			self.pv_e = self.raw_end
			return

		self.raw_end = idx.get(0) + 1
		self.pv_e = self.raw_end - 1
	else:
		self.pv_s = self.raw_end - 1

		while true:
			d := self.read_byte()

			if self.eof:
				self.pv_e = self.raw_end
				return

			if is_space(d):
				self.pv_e = self.raw_end - 1
				return

			if d == 62:
				self.raw_end -= 1
				self.pv_e = self.raw_end
				return

// Advances to the next token and sets `tt`.
fn var Parser.next_token() Int:
	self.raw_start = self.raw_end
	self.data_start = self.raw_end
	self.data_end = self.raw_end

	if self.eof:
		self.tt = T_ERROR
		return self.tt

	if self.raw_tag != RAW_NONE:
		if self.raw_tag == RAW_PLAINTEXT:
			self.raw_end = self.size
			self.eof = true
			self.data_end = self.raw_end
			self.text_is_raw = true
		else:
			self.read_raw_or_rcdata()

		if self.data_end > self.data_start:
			self.tt = T_TEXT
			self.convert_nul = true
			return self.tt

	self.text_is_raw = false
	self.convert_nul = false

	while true:
		// Skip to the next `<`; the bytes before it are text.
		idx := self.src.index_of_byte(60, self.raw_end)

		if idx.is_none():
			self.raw_end = self.size
			self.eof = true
			break

		self.raw_end = idx.get(0) + 1

		c := self.read_byte()
		if self.eof: break

		var token_type = T_ERROR

		if is_alpha(c):
			token_type = T_START
		else if c == 47:
			token_type = T_END
		else if c == 33 or c == 63:
			token_type = T_COMMENT
		else:
			self.raw_end -= 1
			continue

		x := self.raw_end - 2

		if self.raw_start < x:
			self.raw_end = x
			self.data_end = x
			self.tt = T_TEXT
			return self.tt

		if token_type == T_START:
			self.tt = self.read_start_tag()
			return self.tt

		if token_type == T_END:
			d := self.read_byte()
			if self.eof: break

			if d == 62:
				self.tt = T_COMMENT
				return self.tt

			if is_alpha(d):
				self.read_tag(false)

				if self.eof:
					self.tt = T_ERROR
				else:
					self.tt = T_END

				return self.tt

			self.raw_end -= 1
			self.read_until_close_angle()
			self.tt = T_COMMENT
			return self.tt

		if c == 33:
			self.tt = self.read_markup_declaration()
			return self.tt

		self.raw_end -= 1
		self.read_until_close_angle()
		self.tt = T_COMMENT
		return self.tt

	if self.raw_start < self.raw_end:
		self.data_end = self.raw_end
		self.tt = T_TEXT
		return self.tt

	self.tt = T_ERROR
	return self.tt

// ---- tokens ----

// The text of the current token range after newline, NUL and character-reference
// handling.
fn var Parser.token_text() String:
	var s = convert_newlines(
		self.src.decode_utf8_range(self.data_start, self.data_end).get("")
	)
	if (self.convert_nul or self.tt == T_COMMENT) and s.contains("\u{0}"):
		s = s.replace("\u{0}", "\u{FFFD}")
	if not self.text_is_raw and s.contains("&"):
		s = msstd_html_decode(s, false)
	return s

// Fills the current token fields from the tokenizer's last token.
fn var Parser.load_token() Unit:
	self.tok_ty = self.tt
	self.tok_atom = 0
	self.tok_data = ""
	self.tok_n = 0

	if self.tt == T_TEXT or self.tt == T_COMMENT or self.tt == T_DOCTYPE:
		self.tok_data = self.token_text()
		return

	if self.tt == T_ERROR: return

	if self.data_start < self.data_end:
		self.tok_atom = atom_of_range(self.src, self.data_start, self.data_end)
		if self.tok_atom == 0:
			self.tok_data = lowered_text(self.src, self.data_start, self.data_end)

	if self.tt == T_END: return

	for i in 0..self.attr_n:
		key := lowered_text(self.src, self.attr_ks[i], self.attr_ke[i])
		var value = convert_newlines(
			self.src.decode_utf8_range(
				self.attr_vs[i],
				self.attr_ve[i],
			).get("")
		)
		if value.contains("&"): value = msstd_html_decode(value, true)

		if i < self.tok_keys.length():
			self.tok_keys[i] = key
			self.tok_vals[i] = value
			self.tok_nss[i] = ""
		else:
			self.tok_keys.append(key)
			self.tok_vals.append(value)
			self.tok_nss.append("")

	self.tok_n = self.attr_n

// ---- node tree ----

// The name of an element node.
fn Parser.tag_name(n: Int) String:
	a := self.atom[n]
	if a != 0: return atom_name(a)

	return self.data[n].clone()

// The name of the current tag token.
fn Parser.tok_name() String:
	if self.tok_atom != 0: return atom_name(self.tok_atom)
	return self.tok_data.clone()

fn var Parser.alloc(kind: Int, atom: Int, data: String) Int:
	id := self.kind.length()
	self.kind.append(kind)
	self.atom.append(atom)
	self.data.append(data)
	self.ns.append(0)
	self.parent.append(-1)
	self.first.append(-1)
	self.last.append(-1)
	self.prev.append(-1)
	self.next.append(-1)
	self.attr_start.append(self.akey.length())
	self.attr_count.append(0)
	return id

// Links `child` before `old` under `parent`; `old` of -1 appends.
fn var Parser.insert_before(parent: Int, child: Int, old: Int) Unit:
	var before = self.last[parent]
	var after = -1

	if old >= 0:
		before = self.prev[old]
		after = old

	if before >= 0:
		self.next[before] = child
	else:
		self.first[parent] = child

	if after >= 0:
		self.prev[after] = child
	else:
		self.last[parent] = child

	self.parent[child] = parent
	self.prev[child] = before
	self.next[child] = after

fn var Parser.append_child(parent: Int, child: Int) Unit:
	self.insert_before(parent, child, -1)

fn var Parser.remove_child(parent: Int, child: Int) Unit:
	before := self.prev[child]
	after := self.next[child]
	if self.first[parent] == child: self.first[parent] = after
	if after >= 0: self.prev[after] = before
	if self.last[parent] == child: self.last[parent] = before
	if before >= 0: self.next[before] = after
	self.parent[child] = -1
	self.prev[child] = -1
	self.next[child] = -1

fn var Parser.detach(child: Int) Unit:
	p := self.parent[child]
	if p >= 0: self.remove_child(p, child)

fn var Parser.reparent_children(dst: Int, src: Int) Unit:
	while self.first[src] >= 0:
		child := self.first[src]
		self.remove_child(src, child)
		self.append_child(dst, child)

// A copy of the node's type, atom, name and attributes (not its namespace).
fn var Parser.clone_node(n: Int) Int:
	id := self.alloc(self.kind[n], self.atom[n], self.data[n].clone())
	start := self.attr_start[n]
	count := self.attr_count[n]

	for i in 0..count:
		self.akey.append(self.akey[start + i].clone())
		self.aval.append(self.aval[start + i].clone())
		self.ans.append(self.ans[start + i].clone())

	self.attr_count[id] = count
	return id

// ---- stacks ----

fn Parser.oe_top() Int:
	n := self.oe.length()
	if n == 0: return -1

	return self.oe[n - 1]

fn Parser.top() Int:
	n := self.oe.length()
	if n == 0: return 1

	return self.oe[n - 1]

fn Parser.top_atom() Int:
	return self.atom[self.top()]

fn Parser.oe_top_atom() Int:
	n := self.oe.length()
	if n == 0: return 0

	return self.atom[self.oe[n - 1]]

// Computes the scope marks of open element `i` from the entry below it.
fn var Parser.mark(i: Int) Unit:
	n := self.oe[i]
	html := self.ns[n] == NS_HTML
	a := self.atom[n]
	var below_p = 0
	var below_stop = 0

	if i > 0:
		below_p = self.oe_p[i - 1]
		below_stop = self.oe_stop[i - 1]

	var p = below_p
	var stop = below_stop
	if html and a == A_P: p = i + 1
	if (html and a == A_BUTTON) or stop_atom(self.ns[n], a): stop = i + 1

	if i < self.oe_p.length():
		self.oe_p[i] = p
		self.oe_stop[i] = stop
	else:
		self.oe_p.append(p)
		self.oe_stop.append(stop)

fn var Parser.oe_remark(start: Int) Unit:
	while self.oe_p.length() > start:
		self.oe_p.pop()
		self.oe_stop.pop()

	for i in start..self.oe.length():
		self.mark(i)

fn var Parser.oe_push(n: Int) Unit:
	self.oe.append(n)
	self.mark(self.oe.length() - 1)

fn var Parser.oe_pop() Int:
	if self.oe.length() == 0: return -1

	self.oe_p.pop()
	self.oe_stop.pop()
	return self.oe.pop().get(-1)

fn var Parser.oe_truncate(len: Int) Unit:
	while self.oe.length() > len:
		self.oe.pop()
		self.oe_p.pop()
		self.oe_stop.pop()

fn var Parser.oe_insert(at: Int, n: Int) Unit:
	self.oe.insert(at, n)
	self.oe_remark(at)

fn var Parser.oe_set(i: Int, n: Int) Unit:
	self.oe[i] = n
	self.oe_remark(i)

fn var Parser.oe_remove(n: Int) Unit:
	i := self.oe_index(n)

	if i >= 0:
		self.oe.remove(i)
		self.oe_remark(i)

// The position of the last occurrence of `n` in the open elements, or -1.
fn Parser.oe_index(n: Int) Int:
	var i = self.oe.length() - 1

	while i >= 0:
		if self.oe[i] == n: return i

		i -= 1

	return -1

fn Parser.afe_index(n: Int) Int:
	var i = self.afe.length() - 1

	while i >= 0:
		if self.afe[i] == n: return i

		i -= 1

	return -1

fn var Parser.afe_remove(n: Int) Unit:
	i := self.afe_index(n)
	if i >= 0: self.afe.remove(i)

fn var Parser.afe_truncate_pop() Int:
	r := self.afe.pop()
	return r.get(-1)

// Whether an HTML element with the atom is open.
fn Parser.oe_contains(atom: Int) Bool:
	for n in self.oe:
		if self.atom[n] == atom and self.ns[n] == NS_HTML: return true
	return false

fn Parser.is_special_element(n: Int) Bool:
	a := self.atom[n]
	v := self.ns[n]
	if v == NS_HTML: return is_special_atom(a)
	if v == NS_MATH: return is_math_stop(a)

	return is_svg_stop(a)

// ---- scope ----

// The index of the nearest open element matching one of the atoms (-2 as the first atom
// matches any heading) before a boundary of the scope, or -1.
fn Parser.scope_index(s: Int, m1: Int, m2: Int, m3: Int) Int:
	if s == SCOPE_BUTTON and m1 == A_P and m2 == -1:
		mark_p := self.oe_p.get(self.oe.length() - 1, 0)
		mark_stop := self.oe_stop.get(self.oe.length() - 1, 0)
		if mark_p > mark_stop: return mark_p - 1

		return -1

	var i = self.oe.length() - 1

	while i >= 0:
		n := self.oe[i]
		a := self.atom[n]
		v := self.ns[n]

		if v == NS_HTML:
			if tag_matches(a, m1, m2, m3): return i

			if s == SCOPE_LIST_ITEM:
				if a == A_OL or a == A_UL: return -1
			else if s == SCOPE_BUTTON:
				if a == A_BUTTON: return -1
			else if s == SCOPE_TABLE:
				if a == A_HTML or a == A_TABLE or a == A_TEMPLATE: return -1
			else if s == SCOPE_SELECT:
				if a != A_OPTGROUP and a != A_OPTION: return -1

		if s <= SCOPE_BUTTON and stop_atom(v, a): return -1

		i -= 1

	return -1

fn var Parser.pop_until(s: Int, m1: Int, m2: Int, m3: Int) Bool:
	i := self.scope_index(s, m1, m2, m3)
	if i < 0: return false

	self.oe_truncate(i)
	return true

fn Parser.element_in_scope(s: Int, m1: Int, m2: Int, m3: Int) Bool:
	return self.scope_index(s, m1, m2, m3) >= 0

fn var Parser.clear_stack_to_context(s: Int) Unit:
	var i = self.oe.length() - 1

	while i >= 0:
		a := self.atom[self.oe[i]]
		var hit = false

		if s == SCOPE_TABLE:
			hit = a == A_HTML or a == A_TABLE or a == A_TEMPLATE
		else if s == SCOPE_TABLE_ROW:
			hit = a == A_HTML or a == A_TR or a == A_TEMPLATE
		else if s == SCOPE_TABLE_BODY:
			hit = (
				a == A_HTML
				or a == A_TBODY
				or a == A_TFOOT
				or a == A_THEAD
				or a == A_TEMPLATE
			)

		if hit:
			self.oe_truncate(i + 1)
			return

		i -= 1

fn var Parser.parse_generic_raw_text_element() Unit:
	self.add_element()
	self.original_im = self.im
	self.im = IM_TEXT

// Pops elements whose end tags are implied, stopping at `except` (an atom or -1).
fn var Parser.generate_implied_end_tags(skip_atom: Int) Unit:
	var i = self.oe.length()

	while i > 0:
		n := self.oe[i - 1]
		if self.kind[n] != K_ELEMENT: break

		a := self.atom[n]
		if not is_implied_end(a): break
		if a == skip_atom: break

		i -= 1

	self.oe_truncate(i)

fn var Parser.add_child(n: Int) Unit:
	if self.should_foster_parent():
		self.foster_parent(n)
	else:
		self.append_child(self.top(), n)

	if self.kind[n] == K_ELEMENT: self.oe_push(n)

fn Parser.should_foster_parent() Bool:
	return self.foster_parenting and is_table_context(self.top_atom())

fn Parser.oe_last_atom(atom: Int) Int:
	var i = self.oe.length() - 1

	while i >= 0:
		if self.atom[self.oe[i]] == atom: return i

		i -= 1

	return -1

fn var Parser.foster_parent(n: Int) Unit:
	table_i := self.oe_last_atom(A_TABLE)
	template_j := self.oe_last_atom(A_TEMPLATE)

	if template_j >= 0 and (table_i < 0 or template_j > table_i):
		self.append_child(self.oe[template_j], n)
		return

	var table = -1
	if table_i >= 0: table = self.oe[table_i]

	var parent = self.oe[0]

	if table >= 0:
		parent = self.parent[table]
		if parent < 0:
			parent = self.oe[table_i - 1]

	var before = self.last[parent]
	if table >= 0: before = self.prev[table]

	if before >= 0 and self.kind[before] == K_TEXT and self.kind[n] == K_TEXT:
		self.data[before] = self.data[before].concat(self.data[n])
		self.data[n] = ""
		return

	self.insert_before(parent, n, table)

fn var Parser.add_text(text: String) Unit:
	if text == "": return

	if self.should_foster_parent():
		n := self.alloc(K_TEXT, 0, text)
		self.foster_parent(n)
		return

	t := self.top()
	l := self.last[t]

	if l >= 0 and self.kind[l] == K_TEXT:
		self.data[l] = self.data[l].concat(text)
		return

	n := self.alloc(K_TEXT, 0, text)
	self.add_child(n)

fn var Parser.add_comment() Unit:
	n := self.alloc(K_COMMENT, 0, self.tok_data.clone())
	self.add_child(n)

fn var Parser.append_doc_comment() Unit:
	n := self.alloc(K_COMMENT, 0, self.tok_data.clone())
	self.append_child(1, n)

// Copies the current token's attributes onto node `id`, which has none yet.
fn var Parser.set_token_attributes(id: Int) Unit:
	self.attr_start[id] = self.akey.length()

	for i in 0..self.tok_n:
		self.akey.append(self.tok_keys[i].clone())
		self.aval.append(self.tok_vals[i].clone())
		self.ans.append(self.tok_nss[i].clone())

	self.attr_count[id] = self.tok_n

fn var Parser.add_element() Unit:
	var data = ""
	if self.tok_atom == 0: data = self.tok_data.clone()

	id := self.alloc(K_ELEMENT, self.tok_atom, data)
	if self.tok_n > 0: self.set_token_attributes(id)
	self.add_child(id)

// Whether the attributes of node `n` match the current token's attributes exactly.
fn Parser.same_attributes(n: Int) Bool:
	count := self.attr_count[n]
	if count != self.tok_n: return false

	start := self.attr_start[n]

	for i in 0..count:
		var found = false

		for j in 0..self.tok_n:
			if (
				self.akey[start + i] == self.tok_keys[j]
				and self.ans[start + i] == self.tok_nss[j]
				and self.aval[start + i] == self.tok_vals[j]
			):
				found = true
				break

		if not found: return false

	return true

fn var Parser.add_formatting_element() Unit:
	tag_atom := self.tok_atom
	self.add_element()

	var identical = 0
	var i = self.afe.length()

	while i > 0:
		i -= 1

		id := self.afe[i]
		if self.kind[id] == K_MARKER: break
		if (
			self.kind[id] != K_ELEMENT
			or self.ns[id] != NS_HTML
			or self.atom[id] != tag_atom
			or not self.same_attributes(id)
		):
			continue

		identical += 1
		if identical >= 3: self.afe_remove(id)

	self.afe.append(self.top())

fn var Parser.clear_active_formatting_elements() Unit:
	while true:
		n := self.afe_truncate_pop()
		if self.afe.length() == 0 or n < 0 or self.kind[n] == K_MARKER: return

fn var Parser.reconstruct_active_formatting_elements() Unit:
	if self.afe.length() == 0: return

	top := self.afe[self.afe.length() - 1]
	if self.kind[top] == K_MARKER or self.oe_index(top) >= 0: return

	var n = top
	var i = self.afe.length() - 1

	while self.kind[n] != K_MARKER and self.oe_index(n) < 0:
		if i == 0:
			i = -1
			break

		i -= 1
		n = self.afe[i]

	while true:
		i += 1

		clone := self.clone_node(self.afe[i])
		self.add_child(clone)
		self.afe[i] = clone
		if i == self.afe.length() - 1: break

fn var Parser.reset_insertion_mode() Unit:
	var i = self.oe.length() - 1

	while i >= 0:
		n := self.oe[i]
		last := i == 0
		a := self.atom[n]

		if a == A_SELECT:
			if not last:
				first := self.oe[0]
				var ancestor = n

				while ancestor != first:
					idx := self.oe_index(ancestor)
					var at = idx - 1
					if idx < 0: at = 0
					if at < 0: at = 0
					ancestor = self.oe[at]

					anc := self.atom[ancestor]

					if anc == A_TEMPLATE:
						self.im = IM_IN_SELECT
						return

					if anc == A_TABLE:
						self.im = IM_IN_SELECT_IN_TABLE
						return

			self.im = IM_IN_SELECT
			return

		if a == A_TD or a == A_TH:
			self.im = IM_IN_CELL
			return

		if a == A_TR:
			self.im = IM_IN_ROW
			return

		if a == A_TBODY or a == A_THEAD or a == A_TFOOT:
			self.im = IM_IN_TABLE_BODY
			return

		if a == A_CAPTION:
			self.im = IM_IN_CAPTION
			return

		if a == A_COLGROUP:
			self.im = IM_IN_COLUMN_GROUP
			return

		if a == A_TABLE:
			self.im = IM_IN_TABLE
			return

		if a == A_TEMPLATE:
			if self.ns[n] != NS_HTML:
				i -= 1
				continue

			self.im = IM_IN_BODY
			if self.template_stack.length() > 0:
				self.im = self.template_stack[self.template_stack.length() - 1]
			return

		if a == A_HEAD:
			self.im = IM_IN_HEAD
			return

		if a == A_BODY:
			self.im = IM_IN_BODY
			return

		if a == A_FRAMESET:
			self.im = IM_IN_FRAMESET
			return

		if a == A_HTML:
			if self.head < 0:
				self.im = IM_BEFORE_HEAD
			else:
				self.im = IM_AFTER_HEAD

			return

		if last:
			self.im = IM_IN_BODY
			return

		i -= 1

// Adds the current token's attributes that node `dst` lacks, after its own.
fn var Parser.copy_attributes(dst: Int) Unit:
	if self.tok_n == 0: return

	count := self.attr_count[dst]
	start := self.attr_start[dst]
	var keys: List[String] = []
	var vals: List[String] = []
	var nss: List[String] = []

	for i in 0..count:
		keys.append(self.akey[start + i].clone())
		vals.append(self.aval[start + i].clone())
		nss.append(self.ans[start + i].clone())

	for j in 0..self.tok_n:
		var present = false

		for i in 0..count:
			if self.akey[start + i] == self.tok_keys[j]:
				present = true
				break

		if not present:
			keys.append(self.tok_keys[j].clone())
			vals.append(self.tok_vals[j].clone())
			nss.append(self.tok_nss[j].clone())

	self.attr_start[dst] = self.akey.length()
	self.attr_count[dst] = keys.length()

	for k in 0..keys.length():
		self.akey.append(keys[k].clone())
		self.aval.append(vals[k].clone())
		self.ans.append(nss[k].clone())

fn Parser.tok_attr_is_hidden_input() Bool:
	for i in 0..self.tok_n:
		if self.tok_keys[i] == "type" and ascii_equal_fold(self.tok_vals[i], "hidden"): return true
	return false

// Whether an attribute named `key` is in the current token.
fn Parser.tok_has_attr(key: String) Bool:
	for i in 0..self.tok_n:
		if self.tok_keys[i] == key: return true
	return false

fn var Parser.next_is_not_raw_text() Unit:
	self.raw_tag = RAW_NONE

fn var Parser.pop_p() Unit:
	_popped := self.pop_until(SCOPE_BUTTON, A_P, -1, -1)

// Splits leading whitespace off a text token and adds it; true when nothing remains.
fn var Parser.add_leading_whitespace() Bool:
	d := self.tok_data.clone()
	cut := trim_left_len(d)

	if cut > 0:
		ws := d.take(cut)
		self.add_text(ws)
		if cut == d.byte_length(): return true

		self.tok_data = d.drop(cut)

	return false

fn var Parser.trim_tok_left() Bool:
	cut := trim_left_len(self.tok_data)
	if cut > 0: self.tok_data = self.tok_data.drop(cut)
	return self.tok_data == ""

fn var Parser.run_im(im: Int) Bool:
	if im == IM_IN_BODY: return self.in_body_im()
	if im == IM_INITIAL: return self.initial_im()
	if im == IM_BEFORE_HTML: return self.before_html_im()
	if im == IM_BEFORE_HEAD: return self.before_head_im()
	if im == IM_IN_HEAD: return self.in_head_im()
	if im == IM_AFTER_HEAD: return self.after_head_im()
	if im == IM_TEXT: return self.text_im()
	if im == IM_IN_TABLE: return self.in_table_im()
	if im == IM_IN_CAPTION: return self.in_caption_im()
	if im == IM_IN_COLUMN_GROUP: return self.in_column_group_im()
	if im == IM_IN_TABLE_BODY: return self.in_table_body_im()
	if im == IM_IN_ROW: return self.in_row_im()
	if im == IM_IN_CELL: return self.in_cell_im()
	if im == IM_IN_SELECT: return self.in_select_im()
	if im == IM_IN_SELECT_IN_TABLE: return self.in_select_in_table_im()
	if im == IM_IN_TEMPLATE: return self.in_template_im()
	if im == IM_AFTER_BODY: return self.after_body_im()
	if im == IM_IN_FRAMESET: return self.in_frameset_im()
	if im == IM_AFTER_FRAMESET: return self.after_frameset_im()
	if im == IM_AFTER_AFTER_BODY: return self.after_after_body_im()
	if im == IM_AFTER_AFTER_FRAMESET: return self.after_after_frameset_im()

	return true

fn var Parser.initial_im() Bool:
	if self.tok_ty == T_TEXT:
		if self.trim_tok_left(): return true
	else if self.tok_ty == T_COMMENT:
		self.append_doc_comment()
		return true
	else if self.tok_ty == T_DOCTYPE:
		self.quirks = self.add_doctype(self.tok_data.clone())
		self.im = IM_BEFORE_HTML
		return true

	self.quirks = true
	self.im = IM_BEFORE_HTML
	return false

fn var Parser.before_html_im() Bool:
	if self.tok_ty == T_DOCTYPE: return true

	if self.tok_ty == T_TEXT:
		if self.trim_tok_left(): return true
	else if self.tok_ty == T_START:
		if self.tok_atom == A_HTML:
			self.add_element()
			self.im = IM_BEFORE_HEAD
			return true
	else if self.tok_ty == T_END:
		a := self.tok_atom

		if a == A_HEAD or a == A_BODY or a == A_HTML or a == A_BR:
			self.parse_implied_token(T_START, A_HTML)
			return false

		return true
	else if self.tok_ty == T_COMMENT:
		self.append_doc_comment()
		return true

	self.parse_implied_token(T_START, A_HTML)
	return false

fn var Parser.before_head_im() Bool:
	if self.tok_ty == T_TEXT:
		if self.trim_tok_left(): return true
	else if self.tok_ty == T_START:
		if self.tok_atom == A_HEAD:
			self.add_element()
			self.head = self.top()
			self.im = IM_IN_HEAD
			return true

		if self.tok_atom == A_HTML: return self.in_body_im()
	else if self.tok_ty == T_END:
		a := self.tok_atom

		if a == A_HEAD or a == A_BODY or a == A_HTML or a == A_BR:
			self.parse_implied_token(T_START, A_HEAD)
			return false

		return true
	else if self.tok_ty == T_COMMENT:
		self.add_comment()
		return true
	else if self.tok_ty == T_DOCTYPE:
		return true

	self.parse_implied_token(T_START, A_HEAD)
	return false

fn var Parser.in_head_im() Bool:
	if self.tok_ty == T_TEXT:
		if self.add_leading_whitespace(): return true
	else if self.tok_ty == T_START:
		a := self.tok_atom
		if a == A_HTML: return self.in_body_im()

		if (
			a == A_BASE
			or a == A_BASEFONT
			or a == A_BGSOUND
			or a == A_LINK
			or a == A_META
		):
			self.add_element()

			_popped := self.oe_pop()
			self.has_self_closing = false
			return true

		if a == A_NOSCRIPT or a == A_NOFRAMES or a == A_STYLE:
			self.parse_generic_raw_text_element()
			return true

		if a == A_SCRIPT or a == A_TITLE:
			self.add_element()
			self.original_im = self.im
			self.im = IM_TEXT
			return true

		if a == A_HEAD: return true

		if a == A_TEMPLATE:
			for e in self.oe:
				if self.ns[e] != NS_HTML:
					self.im = IM_IGNORE_REMAINING
					return true

			self.add_element()
			self.afe.append(0)
			self.frameset_ok = false
			self.im = IM_IN_TEMPLATE
			self.template_stack.append(IM_IN_TEMPLATE)
			return true
	else if self.tok_ty == T_END:
		a := self.tok_atom

		if a == A_HEAD:
			_popped := self.oe_pop()
			self.im = IM_AFTER_HEAD
			return true

		if a == A_BODY or a == A_HTML or a == A_BR:
			self.parse_implied_token(T_END, A_HEAD)
			return false

		if a == A_TEMPLATE:
			if not self.oe_contains(A_TEMPLATE): return true

			self.generate_implied_end_tags(-1)

			var i = self.oe.length() - 1

			while i >= 0:
				n := self.oe[i]

				if self.ns[n] == NS_HTML and self.atom[n] == A_TEMPLATE:
					self.oe_truncate(i)
					break

				i -= 1

			self.clear_active_formatting_elements()

			_templates := self.template_stack.pop()
			self.reset_insertion_mode()
			return true

		return true
	else if self.tok_ty == T_COMMENT:
		self.add_comment()
		return true
	else if self.tok_ty == T_DOCTYPE:
		return true

	self.parse_implied_token(T_END, A_HEAD)
	return false

fn var Parser.after_head_im() Bool:
	if self.tok_ty == T_TEXT:
		if self.add_leading_whitespace(): return true
	else if self.tok_ty == T_START:
		a := self.tok_atom
		if a == A_HTML: return self.in_body_im()

		if a == A_BODY:
			self.add_element()
			self.frameset_ok = false
			self.im = IM_IN_BODY
			return true

		if a == A_FRAMESET:
			self.add_element()
			self.im = IM_IN_FRAMESET
			return true

		if (
			a == A_BASE
			or a == A_BASEFONT
			or a == A_BGSOUND
			or a == A_LINK
			or a == A_META
			or a == A_NOFRAMES
			or a == A_SCRIPT
			or a == A_STYLE
			or a == A_TEMPLATE
			or a == A_TITLE
		):
			var head = self.head
			if head < 0: head = 1
			self.oe_push(head)

			r := self.in_head_im()
			self.oe_remove(head)
			return r

		if a == A_HEAD: return true
	else if self.tok_ty == T_END:
		a := self.tok_atom
		if a == A_TEMPLATE: return self.in_head_im()
		if a != A_BODY and a != A_HTML and a != A_BR: return true
	else if self.tok_ty == T_COMMENT:
		self.add_comment()
		return true
	else if self.tok_ty == T_DOCTYPE:
		return true

	self.parse_implied_token(T_START, A_BODY)
	self.frameset_ok = true
	return self.tok_ty == T_ERROR

fn var Parser.in_body_im() Bool:
	if self.tok_ty == T_TEXT:
		var d = self.tok_data.clone()
		t := self.oe_top()

		if t >= 0 and self.first[t] < 0:
			a := self.atom[t]
			if a == A_PRE or a == A_LISTING: d = strip_leading_newline(d)

		if d.contains("\u{0}"): d = d.replace("\u{0}", "")
		if d == "": return true

		self.reconstruct_active_formatting_elements()
		if self.frameset_ok and not is_blank(d): self.frameset_ok = false
		self.add_text(d)
	else if self.tok_ty == T_START:
		return self.in_body_start_tag()
	else if self.tok_ty == T_END:
		return self.in_body_end_tag()
	else if self.tok_ty == T_COMMENT:
		self.add_comment()
	else if self.tok_ty == T_ERROR:
		if self.template_stack.length() > 0:
			self.im = IM_IN_TEMPLATE
			return false

		for e in self.oe:
			if not is_end_ok_in_body(self.atom[e]): return true

	return true

fn var Parser.in_body_start_tag() Bool:
	tag := self.tok_atom
	rule := body_start_class(tag)

	if rule == S_HTML:
		if self.oe_contains(A_TEMPLATE): return true

		self.copy_attributes(self.oe[0])
	else if rule == S_HEAD_LIKE:
		return self.in_head_im()
	else if rule == S_BODY:
		if self.oe_contains(A_TEMPLATE): return true

		if self.oe.length() >= 2:
			body := self.oe[1]

			if self.kind[body] == K_ELEMENT and self.atom[body] == A_BODY:
				self.frameset_ok = false
				self.copy_attributes(body)
	else if rule == S_FRAMESET:
		if (
			not self.frameset_ok
			or self.oe.length() < 2
			or self.atom[self.oe[1]] != A_BODY
		):
			return true

		body := self.oe[1]
		self.detach(body)
		self.oe_truncate(1)
		self.add_element()
		self.im = IM_IN_FRAMESET
		return true
	else if rule == S_BLOCK:
		self.pop_p()
		self.add_element()
	else if rule == S_HEADING:
		self.pop_p()
		if is_heading(self.top_atom()): _popped := self.oe_pop()
		self.add_element()
	else if rule == S_PRE:
		self.pop_p()
		self.add_element()
		self.frameset_ok = false
	else if rule == S_FORM:
		if self.form >= 0 and not self.oe_contains(A_TEMPLATE): return true

		self.pop_p()
		self.add_element()
		if not self.oe_contains(A_TEMPLATE): self.form = self.top()
	else if rule == S_LI:
		self.frameset_ok = false
		self.close_list_item(A_LI, -1)
		self.pop_p()
		self.add_element()
	else if rule == S_DD_DT:
		self.frameset_ok = false
		self.close_list_item(A_DD, A_DT)
		self.pop_p()
		self.add_element()
	else if rule == S_PLAINTEXT:
		self.pop_p()
		self.add_element()
	else if rule == S_BUTTON:
		_popped := self.pop_until(SCOPE_DEFAULT, A_BUTTON, -1, -1)
		self.reconstruct_active_formatting_elements()
		self.add_element()
		self.frameset_ok = false
	else if rule == S_ANCHOR:
		var i = self.afe.length()

		while i > 0 and self.kind[self.afe[i - 1]] != K_MARKER:
			i -= 1

			n := self.afe[i]

			if self.kind[n] == K_ELEMENT and self.atom[n] == A_A:
				self.in_body_end_tag_formatting(A_A, "a")
				self.oe_remove(n)
				self.afe_remove(n)
				break

		self.reconstruct_active_formatting_elements()
		self.add_formatting_element()
	else if rule == S_FORMATTING:
		self.reconstruct_active_formatting_elements()
		self.add_formatting_element()
	else if rule == S_NOBR:
		self.reconstruct_active_formatting_elements()

		if self.element_in_scope(SCOPE_DEFAULT, A_NOBR, -1, -1):
			self.in_body_end_tag_formatting(A_NOBR, "nobr")
			self.reconstruct_active_formatting_elements()

		self.add_formatting_element()
	else if rule == S_APPLET:
		self.reconstruct_active_formatting_elements()
		self.add_element()
		self.afe.append(0)
		self.frameset_ok = false
	else if rule == S_TABLE:
		if not self.quirks: self.pop_p()
		self.add_element()
		self.frameset_ok = false
		self.im = IM_IN_TABLE
		return true
	else if rule == S_VOID_REOPEN:
		self.reconstruct_active_formatting_elements()
		self.add_element()

		_popped := self.oe_pop()
		self.has_self_closing = false
		if tag == A_INPUT and self.tok_attr_is_hidden_input(): return true

		self.frameset_ok = false
	else if rule == S_VOID:
		self.add_element()

		_popped := self.oe_pop()
		self.has_self_closing = false
	else if rule == S_HR:
		self.pop_p()
		self.add_element()

		_popped := self.oe_pop()
		self.has_self_closing = false
		self.frameset_ok = false
	else if rule == S_IMAGE:
		self.tok_atom = A_IMG
		self.tok_data = ""
		return false
	else if rule == S_TEXTAREA:
		self.add_element()
		self.original_im = self.im
		self.frameset_ok = false
		self.im = IM_TEXT
	else if rule == S_XMP:
		self.pop_p()
		self.reconstruct_active_formatting_elements()
		self.frameset_ok = false
		self.parse_generic_raw_text_element()
	else if rule == S_IFRAME:
		self.frameset_ok = false
		self.parse_generic_raw_text_element()
	else if rule == S_NOEMBED:
		self.parse_generic_raw_text_element()
	else if rule == S_NOSCRIPT:
		self.parse_generic_raw_text_element()
		return true
	else if rule == S_SELECT:
		self.reconstruct_active_formatting_elements()
		self.add_element()
		self.frameset_ok = false
		self.im = IM_IN_SELECT
		return true
	else if rule == S_OPTION:
		if self.top_atom() == A_OPTION: _popped := self.oe_pop()
		self.reconstruct_active_formatting_elements()
		self.add_element()
	else if rule == S_RUBY_BASE:
		if self.element_in_scope(SCOPE_DEFAULT, A_RUBY, -1, -1): self.generate_implied_end_tags(
			-1
		)
		self.add_element()
	else if rule == S_RUBY_TEXT:
		if self.element_in_scope(SCOPE_DEFAULT, A_RUBY, -1, -1):
			self.generate_implied_end_tags(A_RTC)
		self.add_element()
	else if rule == S_FOREIGN:
		self.reconstruct_active_formatting_elements()

		if tag == A_MATH:
			self.adjust_math_attributes()
		else:
			self.adjust_svg_attributes()

		self.adjust_foreign_attributes()
		self.add_element()

		t := self.top()

		if tag == A_MATH:
			self.ns[t] = NS_MATH
		else:
			self.ns[t] = NS_SVG

		if self.has_self_closing:
			_popped := self.oe_pop()
			self.has_self_closing = false

		return true
	else if rule == S_TABLE_PART:
		return true
	else:
		self.reconstruct_active_formatting_elements()
		self.add_element()

	return true

// The `li` / `dd` / `dt` loop of the start-tag rules: closes an open item of the same
// kind.
fn var Parser.close_list_item(a1: Int, a2: Int) Unit:
	var i = self.oe.length() - 1

	while i >= 0:
		node := self.oe[i]
		a := self.atom[node]

		if a == a1 or a == a2:
			self.oe_truncate(i)
		else if (
			a == A_ADDRESS
			or a == A_DIV
			or a == A_P
			or not self.is_special_element(node)
		):
			i -= 1
			continue

		break

fn var Parser.in_body_end_tag() Bool:
	tag := self.tok_atom
	rule := body_end_class(tag)

	if rule == E_BODY:
		if self.element_in_scope(SCOPE_DEFAULT, A_BODY, -1, -1): self.im = IM_AFTER_BODY
	else if rule == E_HTML:
		if self.element_in_scope(SCOPE_DEFAULT, A_BODY, -1, -1):
			self.parse_implied_token(T_END, A_BODY)
			return false

		return true
	else if rule == E_BLOCK:
		_popped := self.pop_until(SCOPE_DEFAULT, tag, -1, -1)
	else if rule == E_FORM:
		if self.oe_contains(A_TEMPLATE):
			i := self.scope_index(SCOPE_DEFAULT, A_FORM, -1, -1)
			if i < 0: return true

			self.generate_implied_end_tags(-1)
			if self.atom[self.oe[i]] != A_FORM: return true

			_popped := self.pop_until(SCOPE_DEFAULT, A_FORM, -1, -1)
		else:
			node := self.form
			self.form = -1

			i := self.scope_index(SCOPE_DEFAULT, A_FORM, -1, -1)
			if node < 0 or i < 0 or self.oe[i] != node: return true

			self.generate_implied_end_tags(-1)
			self.oe_remove(node)
	else if rule == E_P:
		if not self.element_in_scope(SCOPE_BUTTON, A_P, -1, -1):
			self.parse_implied_token(T_START, A_P)
		self.pop_p()
	else if rule == E_LI:
		_popped := self.pop_until(SCOPE_LIST_ITEM, A_LI, -1, -1)
	else if rule == E_DD_DT:
		_popped := self.pop_until(SCOPE_DEFAULT, tag, -1, -1)
	else if rule == E_HEADING:
		_popped := self.pop_until(SCOPE_DEFAULT, -2, -1, -1)
	else if rule == E_FORMATTING:
		self.in_body_end_tag_formatting(tag, atom_name(tag))
	else if rule == E_APPLET:
		if self.pop_until(SCOPE_DEFAULT, tag, -1, -1): self.clear_active_formatting_elements()
	else if rule == E_BR:
		self.tok_ty = T_START
		return false
	else if rule == E_TEMPLATE:
		return self.in_head_im()
	else:
		self.in_body_end_tag_other(tag, self.tok_data.clone())

	return true

// The adoption agency algorithm.
fn var Parser.in_body_end_tag_formatting(tag_atom: Int, tag_name: String) Unit:
	current := self.oe_top()

	if (
		current >= 0
		and self.tag_name(current) == tag_name
		and self.afe_index(current) < 0
	):
		_popped := self.oe_pop()
		return

	for _round in 0..8:
		var formatting = -1
		var j = self.afe.length() - 1

		while j >= 0:
			n := self.afe[j]
			if self.kind[n] == K_MARKER: break

			if self.atom[n] == tag_atom:
				formatting = n
				break

			j -= 1

		if formatting < 0:
			self.in_body_end_tag_other(tag_atom, tag_name)
			return

		fe_index := self.oe_index(formatting)

		if fe_index < 0:
			self.afe_remove(formatting)
			return

		if not self.element_in_scope(SCOPE_DEFAULT, tag_atom, -1, -1): return

		var furthest = -1

		for k in fe_index..self.oe.length():
			if self.is_special_element(self.oe[k]):
				furthest = self.oe[k]
				break

		if furthest < 0:
			while true:
				e := self.oe_pop()
				if e == formatting or e < 0: break

			self.afe_remove(formatting)
			return

		common_ancestor := self.oe[fe_index - 1]
		var bookmark = self.afe_index(formatting)
		var last_node = furthest
		var node = -1
		var x = self.oe_index(furthest)
		var steps = 0

		while true:
			steps += 1
			x -= 1
			node = self.oe[x]
			if node == formatting: break

			ni := self.afe_index(node)

			if steps > 3 and ni >= 0:
				self.afe_remove(node)
				if ni <= bookmark: bookmark -= 1
				continue

			if ni < 0:
				self.oe_remove(node)
				continue

			clone := self.clone_node(node)
			self.afe[ni] = clone

			oi := self.oe_index(node)
			if oi >= 0: self.oe_set(oi, clone)
			node = clone
			if last_node == furthest: bookmark = self.afe_index(node) + 1
			self.detach(last_node)
			self.append_child(node, last_node)
			last_node = node

		self.detach(last_node)

		if is_table_context(self.atom[common_ancestor]):
			self.foster_parent(last_node)
		else:
			self.append_child(common_ancestor, last_node)

		clone := self.clone_node(formatting)
		self.reparent_children(clone, furthest)
		self.append_child(furthest, clone)

		old := self.afe_index(formatting)
		if old >= 0 and old < bookmark: bookmark -= 1
		self.afe_remove(formatting)

		var at = bookmark
		if at < 0: at = 0
		if at > self.afe.length(): at = self.afe.length()
		self.afe.insert(at, clone)
		self.oe_remove(formatting)

		fi := self.oe_index(furthest)
		var place = 0
		if fi >= 0: place = fi + 1
		self.oe_insert(place, clone)

fn var Parser.in_body_end_tag_other(tag_atom: Int, tag_name: String) Unit:
	var i = self.oe.length() - 1

	while i >= 0:
		n := self.oe[i]

		if self.atom[n] == tag_atom and (tag_atom != 0 or self.data[n] == tag_name):
			self.oe_truncate(i)
			break

		if self.is_special_element(n): break

		i -= 1

fn var Parser.text_im() Bool:
	if self.tok_ty == T_ERROR:
		_popped := self.oe_pop()
	else if self.tok_ty == T_TEXT:
		var d = self.tok_data.clone()
		t := self.oe_top()
		if t >= 0 and self.atom[t] == A_TEXTAREA and self.first[t] < 0:
			d = strip_leading_newline(d)
		if d == "": return true

		self.add_text(d)
		return true
	else if self.tok_ty == T_END:
		_popped := self.oe_pop()

	self.im = IM_IN_BODY
	if self.original_im >= 0: self.im = self.original_im
	self.original_im = -1
	return self.tok_ty == T_END

fn var Parser.in_table_im() Bool:
	if self.tok_ty == T_TEXT:
		if self.tok_data.contains("\u{0}"): self.tok_data = self.tok_data.replace(
			"\u{0}",
			"",
		)

		if is_table_context(self.oe_top_atom()) and is_blank(self.tok_data):
			self.add_text(self.tok_data.clone())
			return true
	else if self.tok_ty == T_START:
		a := self.tok_atom

		if a == A_CAPTION:
			self.clear_stack_to_context(SCOPE_TABLE)
			self.afe.append(0)
			self.add_element()
			self.im = IM_IN_CAPTION
			return true

		if a == A_COLGROUP:
			self.clear_stack_to_context(SCOPE_TABLE)
			self.add_element()
			self.im = IM_IN_COLUMN_GROUP
			return true

		if a == A_COL:
			self.parse_implied_token(T_START, A_COLGROUP)
			return false

		if a == A_TBODY or a == A_TFOOT or a == A_THEAD:
			self.clear_stack_to_context(SCOPE_TABLE)
			self.add_element()
			self.im = IM_IN_TABLE_BODY
			return true

		if a == A_TD or a == A_TH or a == A_TR:
			self.parse_implied_token(T_START, A_TBODY)
			return false

		if a == A_TABLE:
			if self.pop_until(SCOPE_TABLE, A_TABLE, -1, -1):
				self.reset_insertion_mode()
				return false

			return true

		if a == A_STYLE or a == A_SCRIPT or a == A_TEMPLATE: return self.in_head_im()

		if a == A_INPUT:
			if self.tok_attr_is_hidden_input():
				self.add_element()

				_popped := self.oe_pop()
				return true
		else if a == A_FORM:
			if self.oe_contains(A_TEMPLATE) or self.form >= 0: return true

			self.add_element()
			self.form = self.oe_pop()
		else if a == A_SELECT:
			self.reconstruct_active_formatting_elements()
			if is_table_context(self.top_atom()): self.foster_parenting = true
			self.add_element()
			self.foster_parenting = false
			self.frameset_ok = false
			self.im = IM_IN_SELECT_IN_TABLE
			return true
	else if self.tok_ty == T_END:
		a := self.tok_atom

		if a == A_TABLE:
			if self.pop_until(SCOPE_TABLE, A_TABLE, -1, -1): self.reset_insertion_mode()
			return true

		if (
			a == A_BODY
			or a == A_CAPTION
			or a == A_COL
			or a == A_COLGROUP
			or a == A_HTML
			or a == A_TBODY
			or a == A_TD
			or a == A_TFOOT
			or a == A_TH
			or a == A_THEAD
			or a == A_TR
		):
			return true
		if a == A_TEMPLATE: return self.in_head_im()
	else if self.tok_ty == T_COMMENT:
		self.add_comment()
		return true
	else if self.tok_ty == T_DOCTYPE:
		return true
	else if self.tok_ty == T_ERROR:
		return self.in_body_im()

	self.foster_parenting = true

	r := self.in_body_im()
	self.foster_parenting = false
	return r

fn var Parser.in_caption_im() Bool:
	if self.tok_ty == T_START:
		a := self.tok_atom

		if (
			a == A_CAPTION
			or a == A_COL
			or a == A_COLGROUP
			or a == A_TBODY
			or a == A_TD
			or a == A_TFOOT
			or a == A_THEAD
			or a == A_TR
		):
			if not self.pop_until(SCOPE_TABLE, A_CAPTION, -1, -1): return true

			self.clear_active_formatting_elements()
			self.im = IM_IN_TABLE
			return false

		if a == A_SELECT:
			self.reconstruct_active_formatting_elements()
			self.add_element()
			self.frameset_ok = false
			self.im = IM_IN_SELECT_IN_TABLE
			return true
	else if self.tok_ty == T_END:
		a := self.tok_atom

		if a == A_CAPTION:
			if self.pop_until(SCOPE_TABLE, A_CAPTION, -1, -1):
				self.clear_active_formatting_elements()
				self.im = IM_IN_TABLE

			return true

		if a == A_TABLE:
			if not self.pop_until(SCOPE_TABLE, A_CAPTION, -1, -1): return true

			self.clear_active_formatting_elements()
			self.im = IM_IN_TABLE
			return false

		if (
			a == A_BODY
			or a == A_COL
			or a == A_COLGROUP
			or a == A_HTML
			or a == A_TBODY
			or a == A_TD
			or a == A_TFOOT
			or a == A_TH
			or a == A_THEAD
			or a == A_TR
		):
			return true

	return self.in_body_im()

fn var Parser.in_column_group_im() Bool:
	if self.tok_ty == T_TEXT:
		if self.add_leading_whitespace(): return true
	else if self.tok_ty == T_COMMENT:
		self.add_comment()
		return true
	else if self.tok_ty == T_DOCTYPE:
		return true
	else if self.tok_ty == T_START:
		a := self.tok_atom
		if a == A_HTML: return self.in_body_im()

		if a == A_COL:
			self.add_element()

			_popped := self.oe_pop()
			self.has_self_closing = false
			return true

		if a == A_TEMPLATE: return self.in_head_im()
	else if self.tok_ty == T_END:
		a := self.tok_atom

		if a == A_COLGROUP:
			if self.oe_top_atom() == A_COLGROUP:
				_popped := self.oe_pop()
				self.im = IM_IN_TABLE

			return true

		if a == A_COL: return true
		if a == A_TEMPLATE: return self.in_head_im()
	else if self.tok_ty == T_ERROR:
		return self.in_body_im()

	if self.oe_top_atom() != A_COLGROUP: return true

	_popped := self.oe_pop()
	self.im = IM_IN_TABLE
	return false

fn var Parser.in_table_body_im() Bool:
	if self.tok_ty == T_START:
		a := self.tok_atom

		if a == A_TR:
			self.clear_stack_to_context(SCOPE_TABLE_BODY)
			self.add_element()
			self.im = IM_IN_ROW
			return true

		if a == A_TD or a == A_TH:
			self.parse_implied_token(T_START, A_TR)
			return false

		if (
			a == A_CAPTION
			or a == A_COL
			or a == A_COLGROUP
			or a == A_TBODY
			or a == A_TFOOT
			or a == A_THEAD
		):
			if self.pop_until(SCOPE_TABLE, A_TBODY, A_THEAD, A_TFOOT):
				self.im = IM_IN_TABLE
				return false

			return true
	else if self.tok_ty == T_END:
		a := self.tok_atom

		if a == A_TBODY or a == A_TFOOT or a == A_THEAD:
			if self.element_in_scope(SCOPE_TABLE, a, -1, -1):
				self.clear_stack_to_context(SCOPE_TABLE_BODY)

				_popped := self.oe_pop()
				self.im = IM_IN_TABLE

			return true

		if a == A_TABLE:
			if self.pop_until(SCOPE_TABLE, A_TBODY, A_THEAD, A_TFOOT):
				self.im = IM_IN_TABLE
				return false

			return true

		if (
			a == A_BODY
			or a == A_CAPTION
			or a == A_COL
			or a == A_COLGROUP
			or a == A_HTML
			or a == A_TD
			or a == A_TH
			or a == A_TR
		):
			return true
	else if self.tok_ty == T_COMMENT:
		self.add_comment()
		return true

	return self.in_table_im()

fn var Parser.in_row_im() Bool:
	if self.tok_ty == T_START:
		a := self.tok_atom

		if a == A_TD or a == A_TH:
			self.clear_stack_to_context(SCOPE_TABLE_ROW)
			self.add_element()
			self.afe.append(0)
			self.im = IM_IN_CELL
			return true

		if (
			a == A_CAPTION
			or a == A_COL
			or a == A_COLGROUP
			or a == A_TBODY
			or a == A_TFOOT
			or a == A_THEAD
			or a == A_TR
		):
			if self.pop_until(SCOPE_TABLE, A_TR, -1, -1):
				self.im = IM_IN_TABLE_BODY
				return false

			return true
	else if self.tok_ty == T_END:
		a := self.tok_atom

		if a == A_TR:
			if self.pop_until(SCOPE_TABLE, A_TR, -1, -1): self.im = IM_IN_TABLE_BODY
			return true

		if a == A_TABLE:
			if self.pop_until(SCOPE_TABLE, A_TR, -1, -1):
				self.im = IM_IN_TABLE_BODY
				return false

			return true

		if a == A_TBODY or a == A_TFOOT or a == A_THEAD:
			if self.element_in_scope(SCOPE_TABLE, a, -1, -1):
				self.parse_implied_token(T_END, A_TR)
				return false

			return true

		if (
			a == A_BODY
			or a == A_CAPTION
			or a == A_COL
			or a == A_COLGROUP
			or a == A_HTML
			or a == A_TD
			or a == A_TH
		):
			return true

	return self.in_table_im()

fn var Parser.in_cell_im() Bool:
	if self.tok_ty == T_START:
		a := self.tok_atom

		if (
			a == A_CAPTION
			or a == A_COL
			or a == A_COLGROUP
			or a == A_TBODY
			or a == A_TD
			or a == A_TFOOT
			or a == A_TH
			or a == A_THEAD
			or a == A_TR
		):
			if self.pop_until(SCOPE_TABLE, A_TD, A_TH, -1):
				self.clear_active_formatting_elements()
				self.im = IM_IN_ROW
				return false

			return true

		if a == A_SELECT:
			self.reconstruct_active_formatting_elements()
			self.add_element()
			self.frameset_ok = false
			self.im = IM_IN_SELECT_IN_TABLE
			return true
	else if self.tok_ty == T_END:
		a := self.tok_atom

		if a == A_TD or a == A_TH:
			if not self.pop_until(SCOPE_TABLE, a, -1, -1): return true

			self.clear_active_formatting_elements()
			self.im = IM_IN_ROW
			return true

		if (
			a == A_BODY
			or a == A_CAPTION
			or a == A_COL
			or a == A_COLGROUP
			or a == A_HTML
		):
			return true

		if a == A_TABLE or a == A_TBODY or a == A_TFOOT or a == A_THEAD or a == A_TR:
			if not self.element_in_scope(SCOPE_TABLE, a, -1, -1): return true

			if self.pop_until(SCOPE_TABLE, A_TD, A_TH, -1): self.clear_active_formatting_elements()
			self.im = IM_IN_ROW
			return false

	return self.in_body_im()

fn var Parser.in_select_im() Bool:
	if self.tok_ty == T_TEXT:
		d := self.tok_data.replace("\u{0}", "")
		self.add_text(d)
	else if self.tok_ty == T_START:
		a := self.tok_atom
		if a == A_HTML: return self.in_body_im()

		if a == A_OPTION:
			if self.top_atom() == A_OPTION: _popped := self.oe_pop()
			self.add_element()
		else if a == A_OPTGROUP:
			if self.top_atom() == A_OPTION: _popped := self.oe_pop()
			if self.top_atom() == A_OPTGROUP: _popped := self.oe_pop()
			self.add_element()
		else if a == A_SELECT:
			if not self.pop_until(SCOPE_SELECT, A_SELECT, -1, -1): return true

			self.reset_insertion_mode()
		else if a == A_INPUT or a == A_KEYGEN or a == A_TEXTAREA:
			if self.element_in_scope(SCOPE_SELECT, A_SELECT, -1, -1):
				self.parse_implied_token(T_END, A_SELECT)
				return false

			self.next_is_not_raw_text()
			return true
		else if a == A_SCRIPT or a == A_TEMPLATE:
			return self.in_head_im()
		else if (
			a == A_IFRAME
			or a == A_NOEMBED
			or a == A_NOFRAMES
			or a == A_NOSCRIPT
			or a == A_PLAINTEXT
			or a == A_STYLE
			or a == A_TITLE
			or a == A_XMP
		):
			self.next_is_not_raw_text()
			return true
	else if self.tok_ty == T_END:
		a := self.tok_atom

		if a == A_OPTION:
			if self.top_atom() == A_OPTION: _popped := self.oe_pop()
		else if a == A_OPTGROUP:
			var i = self.oe.length() - 1
			if self.atom[self.oe[i]] == A_OPTION: i -= 1
			if self.atom[self.oe[i]] == A_OPTGROUP: self.oe_truncate(i)
		else if a == A_SELECT:
			if not self.pop_until(SCOPE_SELECT, A_SELECT, -1, -1): return true

			self.reset_insertion_mode()
		else if a == A_TEMPLATE:
			return self.in_head_im()
	else if self.tok_ty == T_COMMENT:
		self.add_comment()
	else if self.tok_ty == T_DOCTYPE:
		return true
	else if self.tok_ty == T_ERROR:
		return self.in_body_im()

	return true

fn var Parser.in_select_in_table_im() Bool:
	if self.tok_ty == T_START or self.tok_ty == T_END:
		a := self.tok_atom

		if (
			a == A_CAPTION
			or a == A_TABLE
			or a == A_TBODY
			or a == A_TFOOT
			or a == A_THEAD
			or a == A_TR
			or a == A_TD
			or a == A_TH
		):
			if (
				self.tok_ty == T_END
				and not self.element_in_scope(SCOPE_TABLE, a, -1, -1)
			):
				return true

			var i = self.oe.length() - 1

			while i >= 0:
				if self.atom[self.oe[i]] == A_SELECT:
					self.oe_truncate(i)
					break

				i -= 1

			self.reset_insertion_mode()
			return false

	return self.in_select_im()

fn var Parser.set_template_top(im: Int) Unit:
	_popped := self.template_stack.pop()
	self.template_stack.append(im)
	self.im = im

fn var Parser.in_template_im() Bool:
	if self.tok_ty == T_TEXT or self.tok_ty == T_COMMENT or self.tok_ty == T_DOCTYPE:
		return self.in_body_im()

	if self.tok_ty == T_START:
		a := self.tok_atom
		if (
			a == A_BASE
			or a == A_BASEFONT
			or a == A_BGSOUND
			or a == A_LINK
			or a == A_META
			or a == A_NOFRAMES
			or a == A_SCRIPT
			or a == A_STYLE
			or a == A_TEMPLATE
			or a == A_TITLE
		):
			return self.in_head_im()

		if (
			a == A_CAPTION
			or a == A_COLGROUP
			or a == A_TBODY
			or a == A_TFOOT
			or a == A_THEAD
		):
			self.set_template_top(IM_IN_TABLE)
		else if a == A_COL:
			self.set_template_top(IM_IN_COLUMN_GROUP)
		else if a == A_TR:
			self.set_template_top(IM_IN_TABLE_BODY)
		else if a == A_TD or a == A_TH:
			self.set_template_top(IM_IN_ROW)
		else:
			self.set_template_top(IM_IN_BODY)

		return false

	if self.tok_ty == T_END:
		if self.tok_atom == A_TEMPLATE: return self.in_head_im()
		return true

	if self.tok_ty == T_ERROR:
		if not self.oe_contains(A_TEMPLATE): return true

		self.generate_implied_end_tags(-1)

		var i = self.oe.length() - 1

		while i >= 0:
			n := self.oe[i]

			if self.ns[n] == NS_HTML and self.atom[n] == A_TEMPLATE:
				self.oe_truncate(i)
				break

			i -= 1

		self.clear_active_formatting_elements()

		_popped := self.template_stack.pop()
		self.reset_insertion_mode()
		return false

	return false

fn var Parser.after_body_im() Bool:
	if self.tok_ty == T_ERROR: return true

	if self.tok_ty == T_TEXT:
		if is_blank(self.tok_data): return self.in_body_im()
	else if self.tok_ty == T_START:
		if self.tok_atom == A_HTML: return self.in_body_im()
	else if self.tok_ty == T_END:
		if self.tok_atom == A_HTML:
			self.im = IM_AFTER_AFTER_BODY
			return true
	else if self.tok_ty == T_COMMENT:
		n := self.alloc(K_COMMENT, 0, self.tok_data.clone())
		self.append_child(self.oe[0], n)
		return true

	self.im = IM_IN_BODY
	return false

// The whitespace of the current text token; the framesets keep only that.
fn Parser.tok_whitespace_only() String:
	var out = StringBuilder()
	for c in self.tok_data.chars():
		if c == " " or c == "\t" or c == "\n" or c == "\u{C}" or c == "\r": out.append(
			c
		)
	return out.build()

fn var Parser.in_frameset_im() Bool:
	if self.tok_ty == T_COMMENT:
		self.add_comment()
	else if self.tok_ty == T_TEXT:
		s := self.tok_whitespace_only()
		if s != "": self.add_text(s)
	else if self.tok_ty == T_START:
		a := self.tok_atom
		if a == A_HTML: return self.in_body_im()

		if a == A_FRAMESET:
			self.add_element()
		else if a == A_FRAME:
			self.add_element()

			_popped := self.oe_pop()
			self.has_self_closing = false
		else if a == A_NOFRAMES:
			return self.in_head_im()
	else if (
		self.tok_ty == T_END
		and self.tok_atom == A_FRAMESET
		and self.oe_top_atom() != A_HTML
	):
		_popped := self.oe_pop()

		if self.oe_top_atom() != A_FRAMESET:
			self.im = IM_AFTER_FRAMESET
			return true

	return true

fn var Parser.after_frameset_im() Bool:
	if self.tok_ty == T_COMMENT:
		self.add_comment()
	else if self.tok_ty == T_TEXT:
		s := self.tok_whitespace_only()
		if s != "": self.add_text(s)
	else if self.tok_ty == T_START:
		if self.tok_atom == A_HTML: return self.in_body_im()
		if self.tok_atom == A_NOFRAMES: return self.in_head_im()
	else if self.tok_ty == T_END and self.tok_atom == A_HTML:
		self.im = IM_AFTER_AFTER_FRAMESET
		return true

	return true

fn var Parser.after_after_body_im() Bool:
	if self.tok_ty == T_ERROR: return true

	if self.tok_ty == T_TEXT:
		if is_blank(self.tok_data): return self.in_body_im()
	else if self.tok_ty == T_START:
		if self.tok_atom == A_HTML: return self.in_body_im()
	else if self.tok_ty == T_COMMENT:
		self.append_doc_comment()
		return true
	else if self.tok_ty == T_DOCTYPE:
		return self.in_body_im()

	self.im = IM_IN_BODY
	return false

fn var Parser.after_after_frameset_im() Bool:
	if self.tok_ty == T_COMMENT:
		self.append_doc_comment()
	else if self.tok_ty == T_TEXT:
		s := self.tok_whitespace_only()

		if s != "":
			self.tok_data = s
			return self.in_body_im()
	else if self.tok_ty == T_START:
		if self.tok_atom == A_HTML: return self.in_body_im()
		if self.tok_atom == A_NOFRAMES: return self.in_head_im()
	else if self.tok_ty == T_DOCTYPE:
		return self.in_body_im()

	return true

// ---- foreign content ----

fn var Parser.adjust_math_attributes() Unit:
	for i in 0..self.tok_n:
		if self.tok_keys[i] == "definitionurl": self.tok_keys[i] = "definitionURL"

fn var Parser.adjust_svg_attributes() Unit:
	for i in 0..self.tok_n:
		adjusted := svg_attribute(self.tok_keys[i])
		if adjusted != "": self.tok_keys[i] = adjusted

// Splits the prefix of the namespaced attribute names off into their namespace.
fn var Parser.adjust_foreign_attributes() Unit:
	for i in 0..self.tok_n:
		key := self.tok_keys[i].clone()
		if not key.starts_with("x") or not is_foreign_attribute(key): continue

		colon := key.index_of(":")

		if colon.is_some():
			at := colon.get(0)
			self.tok_nss[i] = key.take(at)
			self.tok_keys[i] = key.drop(at + 1)

fn Parser.html_integration_point(n: Int) Bool:
	if self.kind[n] != K_ELEMENT: return false

	if self.ns[n] == NS_MATH:
		if self.atom[n] != A_ANNOTATION_XML: return false

		start := self.attr_start[n]

		for i in 0..self.attr_count[n]:
			if self.akey[start + i] != "encoding": continue

			value := self.aval[start + i]
			if (
				ascii_equal_fold(value, "text/html")
				or ascii_equal_fold(value, "application/xhtml+xml")
			):
				return true

		return false

	if self.ns[n] == NS_SVG: return is_svg_stop(self.atom[n])

	return false

fn Parser.math_text_integration_point(n: Int) Bool:
	return self.ns[n] == NS_MATH and is_math_text_atom(self.atom[n])

fn Parser.tok_font_has_style_attribute() Bool:
	for i in 0..self.tok_n:
		key := self.tok_keys[i]
		if key == "color" or key == "face" or key == "size": return true

	return false

fn var Parser.parse_foreign_content() Bool:
	if self.tok_ty == T_TEXT:
		if self.frameset_ok:
			cut := self.tok_data.replace("\u{0}", "")
			self.frameset_ok = is_blank(cut)

		self.tok_data = self.tok_data.replace("\u{0}", "\u{FFFD}")
		self.add_text(self.tok_data.clone())
	else if self.tok_ty == T_COMMENT:
		self.add_comment()
	else if self.tok_ty == T_START:
		var breakout = is_breakout_atom(self.tok_atom)
		if self.tok_atom == A_FONT and self.tok_font_has_style_attribute(): breakout = true

		if breakout:
			var i = self.oe.length() - 1

			while i >= 0:
				n := self.oe[i]

				if (
					self.ns[n] == NS_HTML
					or self.html_integration_point(n)
					or self.math_text_integration_point(n)
				):
					self.oe_truncate(i + 1)
					break

				i -= 1

			return false

		current := self.top()
		v := self.ns[current]

		if v == NS_MATH:
			self.adjust_math_attributes()
		else if v == NS_SVG:
			adjusted := svg_tag(self.tok_name())

			if adjusted != "":
				self.tok_atom = atom_of_text(adjusted)
				self.tok_data = adjusted

			self.adjust_svg_attributes()

		self.adjust_foreign_attributes()
		self.add_element()
		self.ns[self.top()] = v
		if v != NS_HTML: self.next_is_not_raw_text()

		if self.has_self_closing:
			_popped := self.oe_pop()
			self.has_self_closing = false
	else if self.tok_ty == T_END:
		var i = self.oe.length() - 1

		while i >= 0:
			n := self.oe[i]
			if self.ns[n] == NS_HTML: return self.run_im(self.im)

			if ascii_equal_fold(self.tag_name(n), self.tok_name()):
				self.oe_truncate(i)
				break

			i -= 1

		return true

	return true

fn Parser.in_foreign_content() Bool:
	n := self.oe_top()
	if n < 0: return false
	if self.ns[n] == NS_HTML: return false

	if self.math_text_integration_point(n):
		if (
			self.tok_ty == T_START
			and self.tok_atom != A_MGLYPH
			and self.tok_atom != A_MALIGNMARK
		):
			return false
		if self.tok_ty == T_TEXT: return false

	if (
		self.ns[n] == NS_MATH
		and self.atom[n] == A_ANNOTATION_XML
		and self.tok_ty == T_START
		and self.tok_atom == A_SVG
	):
		return false
	if (
		self.html_integration_point(n)
		and (self.tok_ty == T_START or self.tok_ty == T_TEXT)
	):
		return false
	if self.tok_ty == T_ERROR: return false

	return true

// Parses a token the document implies, such as the `html` start tag, then restores the
// real one.
fn var Parser.parse_implied_token(ty: Int, atom: Int) Unit:
	real_ty := self.tok_ty
	real_atom := self.tok_atom
	real_data := self.tok_data.clone()
	real_n := self.tok_n
	self_closing := self.has_self_closing
	self.tok_ty = ty
	self.tok_atom = atom
	self.tok_data = ""
	self.tok_n = 0
	self.has_self_closing = false
	self.parse_current_token()
	self.tok_ty = real_ty
	self.tok_atom = real_atom
	self.tok_data = real_data
	self.tok_n = real_n
	self.has_self_closing = self_closing

fn var Parser.parse_current_token() Unit:
	if self.tok_ty == T_SELF_CLOSING:
		self.has_self_closing = true
		self.tok_ty = T_START

	var consumed = false

	while not consumed:
		if self.in_foreign_content():
			consumed = self.parse_foreign_content()
		else:
			consumed = self.run_im(self.im)

	self.has_self_closing = false

fn var Parser.run() Unit:
	while true:
		n := self.oe_top()
		self.allow_cdata = n >= 0 and self.ns[n] != NS_HTML

		_type := self.next_token()
		self.load_token()

		eof := self.tok_ty == T_ERROR
		self.parse_current_token()

		if self.oe.length() > self.max_open:
			self.exceeded = true
			break

		if eof: break

// ---- doctype ----

// Parses the contents of a doctype token into a doctype node under the document,
// returning whether it puts the document in quirks mode.
fn var Parser.add_doctype(text: String) Bool:
	b := text.to_bytes()
	size := b.length()
	var quirks = false
	var space = 0
	while space < size and not is_html_whitespace(b.get(space).to_int()):
		space += 1

	name := b.decode_utf8_range(0, space).get("")
	if name != "html": quirks = true

	node := self.alloc(K_DOCTYPE, 0, go_lower(name))
	self.append_child(1, node)

	var pos = space
	while pos < size and is_html_whitespace(b.get(pos).to_int()):
		pos += 1
	if size - pos < 6: return quirks or pos < size

	var key = go_lower(b.decode_utf8_range(pos, pos + 6).get(""))
	pos += 6
	if not valid_boundary(b, pos): pos = size
	if key == "": key = "?"

	var keys: List[String] = []
	var values: List[String] = []

	while key == "public" or key == "system":
		while pos < size and is_html_whitespace(b.get(pos).to_int()):
			pos += 1
		if pos >= size: break

		quote := b.get(pos).to_int()
		if quote != 34 and quote != 39: break

		pos += 1

		var end = size
		var next = size
		var scan = pos

		while scan < size:
			if b.get(scan).to_int() == quote:
				end = scan
				next = scan + 1
				break

			scan += 1

		keys.append(key.clone())
		values.append(b.decode_utf8_range(pos, end).get(""))
		pos = next

		if key == "public":
			key = "system"
		else:
			key = ""

	self.attr_start[node] = self.akey.length()
	self.attr_count[node] = keys.length()

	for i in 0..keys.length():
		self.akey.append(keys[i].clone())
		self.aval.append(values[i].clone())
		self.ans.append("")

	if key != "" or pos < size: return true

	if keys.length() > 0:
		if keys[0] == "public":
			public_id := go_lower(values[0])

			if (
				public_id == "-//w3o//dtd w3 html strict 3.0//en//"
				or public_id == "-/w3d/dtd html 4.0 transitional/en"
				or public_id == "html"
			):
				quirks = true
			else:
				for id in QUIRKY_IDS:
					if public_id.starts_with(id):
						quirks = true
						break

			if (
				keys.length() == 1
				and (
					public_id.starts_with(
						"-//w3c//dtd html 4.01 frameset//"
					)
					or public_id.starts_with(
						"-//w3c//dtd html 4.01 transitional//"
					)
				)
			):
				quirks = true

		last := keys.length() - 1
		if (
			keys[last] == "system"
			and ascii_equal_fold(
				values[last],
				"http://www.ibm.com/data/dtd/v11/ibmxhtml1-transitional.dtd",
			)
		):
			quirks = true

	return quirks

fn is_space(c: Int) Bool:
	return c == 32 or c == 10 or c == 13 or c == 9 or c == 12

fn is_alpha(c: Int) Bool:
	return (c >= 97 and c <= 122) or (c >= 65 and c <= 90)

fn is_heading(atom: Int) Bool:
	return atom >= A_H1 and atom <= A_H6

// The numeric value of `c` lower-cased when it is an ASCII capital.
fn lower_byte(c: Int) Int:
	if c >= 65 and c <= 90: return c + 32
	return c

// Whether the `length` bytes of `data` at `at` equal `name` ignoring ASCII case.
fn bytes_equal_fold(data: Bytes, at: Int, name: Bytes) Bool:
	for i in 0..name.length():
		if lower_byte(data.get(at + i).to_int()) != name.get(i).to_int(): return false
	return true

// ---- tokenizer ----

// Whether `data[start, end)` has a byte that is an ASCII capital or at least 128.
fn needs_ascii_lowering(src: Bytes, start: Int, end: Int) Bool:
	for i in start..end:
		b := src.get(i).to_int()
		if (b >= 65 and b <= 90) or b >= 128: return true

	return false

// The text of `src[start, end)` with ASCII capitals lower-cased (other scalars
// unchanged).
fn lowered_text(src: Bytes, start: Int, end: Int) String:
	text := src.decode_utf8_range(start, end).get("")
	if not needs_ascii_lowering(src, start, end): return text

	var out = StringBuilder()

	for c in text.chars():
		code := c.scalar_at(0)

		if code >= 65 and code <= 90:
			out.append(c.lower())
		else:
			out.append(c)

	return out.build()

// The atom of the lower-cased name `src[start, end)`, or 0 when it is not a known tag
// name.
fn atom_of_range(src: Bytes, start: Int, end: Int) Int:
	length := end - start
	if length <= 0: return 0

	if length <= 6:
		var key = length
		for i in start..end:
			key = key * 256 + lower_byte(src.get(i).to_int())
		return atom_short(key)

	var hash = 5381
	for i in start..end:
		hash = (hash * 33 + lower_byte(src.get(i).to_int())) % 281474976710656

	candidate := atom_long(hash)
	if candidate == 0: return 0
	if (
		bytes_equal_fold(src, start, atom_name(candidate).to_bytes())
		and length == atom_name(candidate).byte_length()
	):
		return candidate

	return 0

// The atom of a name that is already a string; only a few mixed-case names matter.
fn atom_of_text(name: String) Int:
	if name == "foreignObject": return A_FOREIGNOBJECT
	return 0

// Line breaks are normalized to LF.
fn convert_newlines(text: String) String:
	if not text.contains("\r"): return text.clone()
	return text.replace("\r\n", "\n").replace("\r", "\n")

fn stop_atom(ns: Int, atom: Int) Bool:
	if ns == NS_HTML: return is_scope_stop(atom)
	if ns == NS_MATH: return is_math_stop(atom)

	return is_svg_stop(atom)

fn tag_matches(a: Int, m1: Int, m2: Int, m3: Int) Bool:
	if a == m1 or a == m2 or a == m3: return true
	return m1 == -2 and is_heading(a)

// Equality ignoring ASCII case.
fn ascii_equal_fold(a: String, b: String) Bool:
	ab := a.to_bytes()
	bb := b.to_bytes()
	if ab.length() != bb.length(): return false

	for i in 0..ab.length():
		if lower_byte(ab.get(i).to_int()) != lower_byte(bb.get(i).to_int()): return false
	return true

// The first byte that is not HTML whitespace, or the length of the text.
fn trim_left_len(text: String) Int:
	b := text.to_bytes()
	var i = 0
	while i < b.length() and is_space(b.get(i).to_int()):
		i += 1
	return i

// ---- tree-construction helpers ----

// Removes the first scalars of `text` that are a leading CR and then LF.
fn strip_leading_newline(text: String) String:
	var d = text
	if d.starts_with("\r"): d = d.drop(1)
	if d.starts_with("\n"): d = d.drop(1)
	return d

// Whether the text has no scalar other than HTML whitespace.
fn is_blank(text: String) Bool:
	return trim_left_len(text) == text.byte_length()

fn is_foreign_attribute(key: String) Bool:
	match key:
		"xlink:actuate": return true
		"xlink:arcrole": return true
		"xlink:href": return true
		"xlink:role": return true
		"xlink:show": return true
		"xlink:title": return true
		"xlink:type": return true
		"xml:base": return true
		"xml:lang": return true
		"xml:space": return true
		"xmlns:xlink": return true
		_: return false

QUIRKY_IDS := [
	"+//silmaril//dtd html pro v0r11 19970101//",
	"-//advasoft ltd//dtd html 3.0 aswedit + extensions//",
	"-//as//dtd html 3.0 aswedit + extensions//", "-//ietf//dtd html 2.0 level 1//",
	"-//ietf//dtd html 2.0 level 2//", "-//ietf//dtd html 2.0 strict level 1//",
	"-//ietf//dtd html 2.0 strict level 2//", "-//ietf//dtd html 2.0 strict//",
	"-//ietf//dtd html 2.0//", "-//ietf//dtd html 2.1e//", "-//ietf//dtd html 3.0//",
	"-//ietf//dtd html 3.2 final//", "-//ietf//dtd html 3.2//", "-//ietf//dtd html 3//",
	"-//ietf//dtd html level 0//", "-//ietf//dtd html level 1//",
	"-//ietf//dtd html level 2//", "-//ietf//dtd html level 3//",
	"-//ietf//dtd html strict level 0//", "-//ietf//dtd html strict level 1//",
	"-//ietf//dtd html strict level 2//", "-//ietf//dtd html strict level 3//",
	"-//ietf//dtd html strict//", "-//ietf//dtd html//",
	"-//metrius//dtd metrius presentational//",
	"-//microsoft//dtd internet explorer 2.0 html strict//",
	"-//microsoft//dtd internet explorer 2.0 html//",
	"-//microsoft//dtd internet explorer 2.0 tables//",
	"-//microsoft//dtd internet explorer 3.0 html strict//",
	"-//microsoft//dtd internet explorer 3.0 html//",
	"-//microsoft//dtd internet explorer 3.0 tables//",
	"-//netscape comm. corp.//dtd html//", "-//netscape comm. corp.//dtd strict html//",
	"-//o'reilly and associates//dtd html 2.0//",
	"-//o'reilly and associates//dtd html extended 1.0//",
	"-//o'reilly and associates//dtd html extended relaxed 1.0//",
	"-//softquad software//dtd hotmetal pro 6.0::19990601::extensions to html 4.0//",
	"-//softquad//dtd hotmetal pro 4.0::19971010::extensions to html 4.0//",
	"-//spyglass//dtd html 2.0 extended//",
	"-//sq//dtd html 2.0 hotmetal + extensions//",
	"-//sun microsystems corp.//dtd hotjava html//",
	"-//sun microsystems corp.//dtd hotjava strict html//",
	"-//w3c//dtd html 3 1995-03-24//", "-//w3c//dtd html 3.2 draft//",
	"-//w3c//dtd html 3.2 final//", "-//w3c//dtd html 3.2//",
	"-//w3c//dtd html 3.2s draft//", "-//w3c//dtd html 4.0 frameset//",
	"-//w3c//dtd html 4.0 transitional//", "-//w3c//dtd html experimental 19960712//",
	"-//w3c//dtd html experimental 970421//", "-//w3c//dtd w3 html//",
	"-//w3o//dtd w3 html 3.0//", "-//webtechs//dtd mozilla html 2.0//",
	"-//webtechs//dtd mozilla html//"
]

// Lower-cases each scalar with its single-scalar mapping, as Go's `strings.ToLower`
// does.
fn go_lower(text: String) String:
	var out = StringBuilder()

	for c in text.chars():
		lowered := c.lower()

		if lowered.scalar_length() == 1:
			out.append(lowered)
		else if c == "\u{130}":
			out.append("i")
		else:
			out.append(c)

	return out.build()

fn is_html_whitespace(b: Int) Bool:
	return is_space(b)

// Whether `pos` is the start of a UTF-8 scalar (or the end) in `b`.
fn valid_boundary(b: Bytes, pos: Int) Bool:
	if pos >= b.length(): return true
	return b.get(pos).to_int() < 128 or b.get(pos).to_int() >= 192

// ---- generated atom tables (HTML tag names from the Go html atom table) ----

A_A := 1
A_ADDRESS := 8
A_ANNOTATION_XML := 15
A_APPLET := 16
A_AREA := 17
A_ARTICLE := 18
A_ASIDE := 20
A_B := 26
A_BASE := 27
A_BASEFONT := 28
A_BGSOUND := 31
A_BIG := 32
A_BLOCKQUOTE := 34
A_BODY := 35
A_BR := 36
A_BUTTON := 37
A_CAPTION := 39
A_CENTER := 40
A_CODE := 46
A_COL := 47
A_COLGROUP := 48
A_DD := 62
A_DESC := 66
A_DETAILS := 67
A_DIALOG := 69
A_DIR := 70
A_DIV := 73
A_DL := 74
A_DT := 78
A_EM := 79
A_EMBED := 80
A_FIELDSET := 83
A_FIGCAPTION := 84
A_FIGURE := 85
A_FONT := 86
A_FOOTER := 87
A_FOREIGNOBJECT := 89
A_FORM := 91
A_FRAME := 97
A_FRAMESET := 98
A_H1 := 99
A_H2 := 100
A_H3 := 101
A_H4 := 102
A_H5 := 103
A_H6 := 104
A_HEAD := 105
A_HEADER := 106
A_HGROUP := 109
A_HR := 112
A_HTML := 115
A_I := 117
A_IFRAME := 120
A_IMAGE := 121
A_IMG := 122
A_INPUT := 123
A_KEYGEN := 136
A_LI := 142
A_LINK := 143
A_LISTING := 145
A_MAIN := 148
A_MALIGNMARK := 149
A_MARQUEE := 153
A_MATH := 154
A_MENU := 159
A_META := 161
A_MGLYPH := 164
A_MI := 165
A_MN := 168
A_MO := 169
A_MS := 170
A_MTEXT := 171
A_NAV := 175
A_NOBR := 176
A_NOEMBED := 177
A_NOFRAMES := 178
A_NOSCRIPT := 181
A_OBJECT := 183
A_OL := 184
A_OPTGROUP := 272
A_OPTION := 274
A_P := 276
A_PARAM := 277
A_PLAINTEXT := 282
A_PRE := 285
A_RB := 292
A_RP := 300
A_RT := 301
A_RTC := 302
A_RUBY := 303
A_S := 304
A_SCRIPT := 309
A_SEARCH := 311
A_SECTION := 312
A_SELECT := 313
A_SMALL := 319
A_SOURCE := 322
A_STRIKE := 332
A_STRONG := 333
A_STYLE := 334
A_SUMMARY := 336
A_SVG := 338
A_TABLE := 341
A_TBODY := 343
A_TD := 344
A_TEMPLATE := 345
A_TEXTAREA := 346
A_TFOOT := 347
A_TH := 348
A_THEAD := 349
A_TITLE := 351
A_TR := 352
A_TRACK := 353
A_TT := 355
A_U := 358
A_UL := 359
A_WBR := 365
A_XMP := 369

// Atom for a lower-case name packed as length then up to six bytes, or 0.
fn atom_short(key: Int) Int:
	match key:
		353: return 1
		18813706866: return 2
		1795929357512820: return 3
		1795929642987374: return 7
		5915988813678: return 9
		56716404: return 13
		1795985410647412: return 16
		18814756193: return 17
		156019: return 19
		5916106253413: return 20
		5916107304547: return 21
		5916139481455: return 22
		354: return 26
		18830422885: return 27
		56779881: return 29
		56779887: return 30
		56781159: return 32
		5920283782763: return 33
		18831336569: return 35
		156274: return 36
		1797106464747374: return 37
		1798119976493427: return 38
		1798137156232562: return 40
		18847724645: return 44
		5924578227059: return 45
		18848113765: return 46
		56848236: return 47
		5924629278578: return 49
		18848115827: return 50
		1798180122551411: return 57
		18863977569: return 59
		156772: return 62
		5928756077938: return 64
		56911212: return 65
		18864239459: return 66
		56911470: return 68
		1799253629103975: return 69
		56912242: return 70
		56912246: return 73
		156780: return 74
		156788: return 78
		157037: return 79
		5933185000804: return 80
		18897527653: return 82
		1801452753613413: return 85
		18898447988: return 86
		1801478657566066: return 87
		57044850: return 88
		18898449005: return 91
		5937563790693: return 97
		157745: return 99
		157746: return 100
		157747: return 101
		157748: return 102
		157749: return 103
		157750: return 104
		18931343716: return 105
		1803634495219058: return 106
		1803634629634164: return 108
		1803643371091312: return 109
		1803651725419886: return 110
		18931607400: return 111
		157810: return 112
		18932196710: return 113
		18932329836: return 115
		361: return 117
		18947993454: return 118
		158052: return 119
		1804738586832229: return 120
		5950364804965: return 121
		57240935: return 122
		5950382568820: return 123
		57241203: return 125
		158067: return 127
		5950466253168: return 129
		1804798499055972: return 130
		57369188: return 135
		1806933432952174: return 136
		18981940836: return 138
		5963048445292: return 139
		18998193767: return 140
		1808032642461284: return 141
		158825: return 142
		18998718059: return 143
		18998719348: return 144
		18999111536: return 146
		57438071: return 147
		19014969710: return 148
		57500016: return 151
		19014972011: return 152
		19014972520: return 154
		57500024: return 155
		5967410653537: return 157
		19015233141: return 159
		19015234657: return 161
		5967411701106: return 162
		1809132372389732: return 163
		1809140829220968: return 164
		159081: return 165
		57502062: return 166
		159086: return 168
		159087: return 169
		159091: return 170
		5967662381172: return 171
		5967680136548: return 173
		19031747941: return 174
		57565558: return 175
		19032662642: return 176
		5971874046821: return 180
		1811318342771572: return 183
		159596: return 184
		1811369748624754: return 192
		1811369765597305: return 200
		5976151520628: return 202
		1811369782567271: return 204
		1811369782570864: return 211
		1811369916588388: return 224
		1811369983500665: return 245
		1811370033573751: return 258
		1811370034033268: return 259
		19049506158: return 271
		1811378640351086: return 274
		1811400115647860: return 275
		368: return 276
		5980229362029: return 277
		19065826919: return 280
		1812473840952690: return 284
		57700965: return 285
		1812486658289780: return 288
		1812499325020515: return 289
		369: return 290
		160354: return 292
		57828716: return 295
		19099776883: return 298
		160368: return 300
		160372: return 301
		57832547: return 302
		19100164729: return 303
		371: return 304
		19115634032: return 305
		5993147625573: return 307
		1815720768857444: return 308
		1815720818733172: return 309
		1815729124041576: return 311
		1815729307738996: return 313
		5993230594149: return 315
		19116161637: return 316
		5993249006963: return 317
		19116355444: return 318
		5993314479212: return 319
		1815772359058788: return 321
		1815772409258853: return 322
		1815776367699314: return 323
		19116613998: return 324
		57897571: return 326
		1815784991256419: return 327
		1815784992236916: return 329
		5993431921268: return 330
		19116877168: return 331
		1815793833175909: return 332
		1815793833569895: return 333
		5993433492581: return 334
		57898338: return 335
		57898352: return 337
		57898599: return 338
		1815815325508973: return 339
		5997408185445: return 341
		1816811740292468: return 342
		5997425812601: return 343
		160868: return 344
		5997492924276: return 347
		160872: return 348
		5997525819748: return 349
		19132935525: return 350
		5997543582821: return 351
		160882: return 352
		5997693330283: return 353
		160884: return 355
		19133984869: return 356
		373: return 358
		161132: return 359
		1817988343619952: return 361
		6005998777701: return 362
		58089842: return 363
		6006132467055: return 364
		58155634: return 365
		6010427438184: return 366
		19183853936: return 368
		58223984: return 369
		_: return 0

// Atom for a longer lower-case name from its hash; the caller verifies the name.
fn atom_long(hash: Int) Int:
	match hash:
		75709808377100: return 4
		212666035018592: return 5
		229459127764030: return 6
		229459150394347: return 8
		1628798302871: return 10
		143892782447883: return 11
		200171877114755: return 12
		278531945027264: return 14
		86634213961918: return 15
		229459716938729: return 18
		194029230122231: return 23
		213455497732670: return 24
		253825146487604: return 25
		253841884220919: return 28
		229460576966743: return 31
		40682423108254: return 34
		229461630231251: return 39
		215689626680520: return 41
		229461886328879: return 42
		229461890524780: return 43
		253902312071024: return 48
		229462173354293: return 51
		229462174308676: return 52
		229462175750528: return 53
		261718652188186: return 54
		197894262714719: return 55
		253902405758489: return 56
		57035255204631: return 58
		253927155707835: return 60
		253927160738802: return 61
		229463065711754: return 63
		229463082301579: return 67
		229463236929797: return 71
		253937447959613: return 72
		253945369088477: return 75
		217522017965310: return 76
		253948933284630: return 77
		229464706527773: return 81
		254022150074709: return 83
		221767794735049: return 84
		153391350516134: return 90
		230687948579959: return 92
		12883508557841: return 93
		230688420575418: return 94
		106729841165280: return 95
		230688689706208: return 96
		254033617966716: return 98
		229468225744609: return 107
		254119003325036: return 114
		49155062290748: return 116
		224403523061754: return 124
		224408047524068: return 126
		229470074953305: return 128
		254164213167701: return 131
		229470109324305: return 132
		224644712943918: return 133
		254164213319094: return 134
		229472129207312: return 137
		229473570083839: return 145
		254143013095176: return 149
		254310496149660: return 150
		229474547187701: return 153
		229485079540173: return 156
		259427457105554: return 158
		254315676376265: return 160
		229813112404299: return 167
		254336260402929: return 172
		229476370969759: return 177
		254370892562912: return 178
		254371163069640: return 179
		254371384141143: return 181
		39185283551852: return 182
		229477618177946: return 185
		81086033540641: return 186
		107182834625652: return 187
		77570281223870: return 188
		83321664197270: return 189
		201092964985602: return 190
		162143571221432: return 191
		254412082427368: return 193
		232824395968682: return 194
		204547524255019: return 195
		254412090273672: return 196
		229477620902120: return 197
		229477620909176: return 198
		237910277504316: return 199
		219128402439845: return 201
		83424512010074: return 203
		232826336990711: return 205
		220401943314750: return 206
		83444749516922: return 207
		220401951272621: return 208
		83444749873980: return 209
		220401960113006: return 210
		2319281517582: return 212
		232827451041770: return 213
		229477623340450: return 214
		229477623499788: return 215
		229477624561762: return 216
		117420063389388: return 217
		229477628097746: return 218
		232832662485161: return 219
		232834896871875: return 220
		83727239903704: return 221
		229477630155952: return 222
		226079766973516: return 223
		40508520717637: return 225
		8561555269772: return 226
		232836551220473: return 227
		231525256323824: return 228
		232837473215559: return 229
		257538629732977: return 230
		232958064169859: return 231
		87791747564169: return 232
		87791755522040: return 233
		232958064493250: return 234
		83825238029315: return 235
		232958064572199: return 236
		232837866946160: return 237
		87791768678784: return 238
		232840079627301: return 239
		254412567404007: return 240
		83934448408985: return 241
		83934448803584: return 242
		229477635935231: return 243
		229477635937376: return 244
		232841600445206: return 246
		83952898205042: return 247
		83956719174967: return 248
		18623698026676: return 249
		236419199961877: return 250
		229477638450341: return 251
		254412674388852: return 252
		254412711122545: return 253
		84301604030783: return 254
		254412713022611: return 255
		232845205141928: return 256
		254412713267586: return 257
		232845787468043: return 260
		232845804274647: return 261
		254412731891862: return 262
		232845848086436: return 263
		122400320694196: return 264
		254412764084964: return 265
		154451805055096: return 266
		254412802222469: return 267
		67517188597312: return 268
		232850219539349: return 269
		229477644472503: return 270
		254415337937861: return 272
		229477719230704: return 273
		229478424054275: return 278
		229478716994177: return 279
		246929790499816: return 281
		234143297985054: return 282
		247885514752077: return 283
		229479071289964: return 286
		254460343628858: return 287
		204384815827201: return 291
		254528239879715: return 293
		243421917184946: return 294
		254528885995142: return 296
		254529063021893: return 297
		229481558418959: return 299
		229482290764308: return 306
		254570868878594: return 310
		229482434843354: return 312
		254571289572974: return 314
		254584456762593: return 320
		271938799828931: return 325
		229482943307215: return 328
		229483072608691: return 336
		254608355911732: return 340
		254613960499713: return 345
		254614395355427: return 346
		240024844430451: return 354
		218260403063581: return 357
		273661053224476: return 360
		175255844693089: return 367
		_: return 0

// The name of an atom.
fn atom_name(atom: Int) String:
	match atom:
		1: return "a"
		2: return "abbr"
		3: return "accept"
		4: return "accept-charset"
		5: return "accesskey"
		6: return "acronym"
		7: return "action"
		8: return "address"
		9: return "align"
		10: return "allowfullscreen"
		11: return "allowpaymentrequest"
		12: return "allowusermedia"
		13: return "alt"
		14: return "annotation"
		15: return "annotation-xml"
		16: return "applet"
		17: return "area"
		18: return "article"
		19: return "as"
		20: return "aside"
		21: return "async"
		22: return "audio"
		23: return "autocomplete"
		24: return "autofocus"
		25: return "autoplay"
		26: return "b"
		27: return "base"
		28: return "basefont"
		29: return "bdi"
		30: return "bdo"
		31: return "bgsound"
		32: return "big"
		33: return "blink"
		34: return "blockquote"
		35: return "body"
		36: return "br"
		37: return "button"
		38: return "canvas"
		39: return "caption"
		40: return "center"
		41: return "challenge"
		42: return "charset"
		43: return "checked"
		44: return "cite"
		45: return "class"
		46: return "code"
		47: return "col"
		48: return "colgroup"
		49: return "color"
		50: return "cols"
		51: return "colspan"
		52: return "command"
		53: return "content"
		54: return "contenteditable"
		55: return "contextmenu"
		56: return "controls"
		57: return "coords"
		58: return "crossorigin"
		59: return "data"
		60: return "datalist"
		61: return "datetime"
		62: return "dd"
		63: return "default"
		64: return "defer"
		65: return "del"
		66: return "desc"
		67: return "details"
		68: return "dfn"
		69: return "dialog"
		70: return "dir"
		71: return "dirname"
		72: return "disabled"
		73: return "div"
		74: return "dl"
		75: return "download"
		76: return "draggable"
		77: return "dropzone"
		78: return "dt"
		79: return "em"
		80: return "embed"
		81: return "enctype"
		82: return "face"
		83: return "fieldset"
		84: return "figcaption"
		85: return "figure"
		86: return "font"
		87: return "footer"
		88: return "for"
		89: return "foreignObject"
		90: return "foreignobject"
		91: return "form"
		92: return "formaction"
		93: return "formenctype"
		94: return "formmethod"
		95: return "formnovalidate"
		96: return "formtarget"
		97: return "frame"
		98: return "frameset"
		99: return "h1"
		100: return "h2"
		101: return "h3"
		102: return "h4"
		103: return "h5"
		104: return "h6"
		105: return "head"
		106: return "header"
		107: return "headers"
		108: return "height"
		109: return "hgroup"
		110: return "hidden"
		111: return "high"
		112: return "hr"
		113: return "href"
		114: return "hreflang"
		115: return "html"
		116: return "http-equiv"
		117: return "i"
		118: return "icon"
		119: return "id"
		120: return "iframe"
		121: return "image"
		122: return "img"
		123: return "input"
		124: return "inputmode"
		125: return "ins"
		126: return "integrity"
		127: return "is"
		128: return "isindex"
		129: return "ismap"
		130: return "itemid"
		131: return "itemprop"
		132: return "itemref"
		133: return "itemscope"
		134: return "itemtype"
		135: return "kbd"
		136: return "keygen"
		137: return "keytype"
		138: return "kind"
		139: return "label"
		140: return "lang"
		141: return "legend"
		142: return "li"
		143: return "link"
		144: return "list"
		145: return "listing"
		146: return "loop"
		147: return "low"
		148: return "main"
		149: return "malignmark"
		150: return "manifest"
		151: return "map"
		152: return "mark"
		153: return "marquee"
		154: return "math"
		155: return "max"
		156: return "maxlength"
		157: return "media"
		158: return "mediagroup"
		159: return "menu"
		160: return "menuitem"
		161: return "meta"
		162: return "meter"
		163: return "method"
		164: return "mglyph"
		165: return "mi"
		166: return "min"
		167: return "minlength"
		168: return "mn"
		169: return "mo"
		170: return "ms"
		171: return "mtext"
		172: return "multiple"
		173: return "muted"
		174: return "name"
		175: return "nav"
		176: return "nobr"
		177: return "noembed"
		178: return "noframes"
		179: return "nomodule"
		180: return "nonce"
		181: return "noscript"
		182: return "novalidate"
		183: return "object"
		184: return "ol"
		185: return "onabort"
		186: return "onafterprint"
		187: return "onautocomplete"
		188: return "onautocompleteerror"
		189: return "onauxclick"
		190: return "onbeforeprint"
		191: return "onbeforeunload"
		192: return "onblur"
		193: return "oncancel"
		194: return "oncanplay"
		195: return "oncanplaythrough"
		196: return "onchange"
		197: return "onclick"
		198: return "onclose"
		199: return "oncontextmenu"
		200: return "oncopy"
		201: return "oncuechange"
		202: return "oncut"
		203: return "ondblclick"
		204: return "ondrag"
		205: return "ondragend"
		206: return "ondragenter"
		207: return "ondragexit"
		208: return "ondragleave"
		209: return "ondragover"
		210: return "ondragstart"
		211: return "ondrop"
		212: return "ondurationchange"
		213: return "onemptied"
		214: return "onended"
		215: return "onerror"
		216: return "onfocus"
		217: return "onhashchange"
		218: return "oninput"
		219: return "oninvalid"
		220: return "onkeydown"
		221: return "onkeypress"
		222: return "onkeyup"
		223: return "onlanguagechange"
		224: return "onload"
		225: return "onloadeddata"
		226: return "onloadedmetadata"
		227: return "onloadend"
		228: return "onloadstart"
		229: return "onmessage"
		230: return "onmessageerror"
		231: return "onmousedown"
		232: return "onmouseenter"
		233: return "onmouseleave"
		234: return "onmousemove"
		235: return "onmouseout"
		236: return "onmouseover"
		237: return "onmouseup"
		238: return "onmousewheel"
		239: return "onoffline"
		240: return "ononline"
		241: return "onpagehide"
		242: return "onpageshow"
		243: return "onpaste"
		244: return "onpause"
		245: return "onplay"
		246: return "onplaying"
		247: return "onpopstate"
		248: return "onprogress"
		249: return "onratechange"
		250: return "onrejectionhandled"
		251: return "onreset"
		252: return "onresize"
		253: return "onscroll"
		254: return "onsecuritypolicyviolation"
		255: return "onseeked"
		256: return "onseeking"
		257: return "onselect"
		258: return "onshow"
		259: return "onsort"
		260: return "onstalled"
		261: return "onstorage"
		262: return "onsubmit"
		263: return "onsuspend"
		264: return "ontimeupdate"
		265: return "ontoggle"
		266: return "onunhandledrejection"
		267: return "onunload"
		268: return "onvolumechange"
		269: return "onwaiting"
		270: return "onwheel"
		271: return "open"
		272: return "optgroup"
		273: return "optimum"
		274: return "option"
		275: return "output"
		276: return "p"
		277: return "param"
		278: return "pattern"
		279: return "picture"
		280: return "ping"
		281: return "placeholder"
		282: return "plaintext"
		283: return "playsinline"
		284: return "poster"
		285: return "pre"
		286: return "preload"
		287: return "progress"
		288: return "prompt"
		289: return "public"
		290: return "q"
		291: return "radiogroup"
		292: return "rb"
		293: return "readonly"
		294: return "referrerpolicy"
		295: return "rel"
		296: return "required"
		297: return "reversed"
		298: return "rows"
		299: return "rowspan"
		300: return "rp"
		301: return "rt"
		302: return "rtc"
		303: return "ruby"
		304: return "s"
		305: return "samp"
		306: return "sandbox"
		307: return "scope"
		308: return "scoped"
		309: return "script"
		310: return "seamless"
		311: return "search"
		312: return "section"
		313: return "select"
		314: return "selected"
		315: return "shape"
		316: return "size"
		317: return "sizes"
		318: return "slot"
		319: return "small"
		320: return "sortable"
		321: return "sorted"
		322: return "source"
		323: return "spacer"
		324: return "span"
		325: return "spellcheck"
		326: return "src"
		327: return "srcdoc"
		328: return "srclang"
		329: return "srcset"
		330: return "start"
		331: return "step"
		332: return "strike"
		333: return "strong"
		334: return "style"
		335: return "sub"
		336: return "summary"
		337: return "sup"
		338: return "svg"
		339: return "system"
		340: return "tabindex"
		341: return "table"
		342: return "target"
		343: return "tbody"
		344: return "td"
		345: return "template"
		346: return "textarea"
		347: return "tfoot"
		348: return "th"
		349: return "thead"
		350: return "time"
		351: return "title"
		352: return "tr"
		353: return "track"
		354: return "translate"
		355: return "tt"
		356: return "type"
		357: return "typemustmatch"
		358: return "u"
		359: return "ul"
		360: return "updateviacache"
		361: return "usemap"
		362: return "value"
		363: return "var"
		364: return "video"
		365: return "wbr"
		366: return "width"
		367: return "workertype"
		368: return "wrap"
		369: return "xmp"
		_: return ""

// HTML special elements (by atom).
fn is_special_atom(atom: Int) Bool:
	match atom:
		8: return true
		16: return true
		17: return true
		18: return true
		20: return true
		27: return true
		28: return true
		31: return true
		34: return true
		35: return true
		36: return true
		37: return true
		39: return true
		40: return true
		47: return true
		48: return true
		62: return true
		67: return true
		70: return true
		73: return true
		74: return true
		78: return true
		80: return true
		83: return true
		84: return true
		85: return true
		87: return true
		91: return true
		97: return true
		98: return true
		99: return true
		100: return true
		101: return true
		102: return true
		103: return true
		104: return true
		105: return true
		106: return true
		109: return true
		112: return true
		115: return true
		120: return true
		122: return true
		123: return true
		136: return true
		142: return true
		143: return true
		145: return true
		148: return true
		153: return true
		159: return true
		161: return true
		175: return true
		177: return true
		178: return true
		181: return true
		183: return true
		184: return true
		276: return true
		277: return true
		282: return true
		285: return true
		309: return true
		312: return true
		313: return true
		322: return true
		334: return true
		336: return true
		341: return true
		343: return true
		344: return true
		345: return true
		346: return true
		347: return true
		348: return true
		349: return true
		351: return true
		352: return true
		353: return true
		359: return true
		365: return true
		369: return true
		_: return false

// Elements whose end tags are implied.
fn is_implied_end(atom: Int) Bool:
	match atom:
		62: return true
		78: return true
		142: return true
		272: return true
		274: return true
		276: return true
		292: return true
		300: return true
		301: return true
		302: return true
		_: return false

// HTML default-scope boundaries.
fn is_scope_stop(atom: Int) Bool:
	match atom:
		16: return true
		39: return true
		115: return true
		341: return true
		344: return true
		348: return true
		153: return true
		183: return true
		345: return true
		_: return false

// MathML default-scope boundaries.
fn is_math_stop(atom: Int) Bool:
	match atom:
		15: return true
		165: return true
		168: return true
		169: return true
		170: return true
		171: return true
		_: return false

// SVG default-scope boundaries.
fn is_svg_stop(atom: Int) Bool:
	match atom:
		66: return true
		89: return true
		351: return true
		_: return false

// Table, section and row elements.
fn is_table_context(atom: Int) Bool:
	match atom:
		341: return true
		343: return true
		347: return true
		349: return true
		352: return true
		_: return false

// Tags that leave foreign content.
fn is_breakout_atom(atom: Int) Bool:
	match atom:
		26: return true
		32: return true
		34: return true
		35: return true
		36: return true
		40: return true
		46: return true
		62: return true
		73: return true
		74: return true
		78: return true
		79: return true
		80: return true
		99: return true
		100: return true
		101: return true
		102: return true
		103: return true
		104: return true
		105: return true
		112: return true
		117: return true
		122: return true
		142: return true
		145: return true
		159: return true
		161: return true
		176: return true
		184: return true
		276: return true
		285: return true
		303: return true
		304: return true
		319: return true
		324: return true
		333: return true
		332: return true
		335: return true
		337: return true
		341: return true
		355: return true
		358: return true
		359: return true
		363: return true
		_: return false

// MathML text integration points.
fn is_math_text_atom(atom: Int) Bool:
	match atom:
		165: return true
		169: return true
		168: return true
		170: return true
		171: return true
		_: return false

// Open elements allowed at end of input.
fn is_end_ok_in_body(atom: Int) Bool:
	match atom:
		62: return true
		78: return true
		142: return true
		272: return true
		274: return true
		276: return true
		292: return true
		300: return true
		301: return true
		302: return true
		343: return true
		344: return true
		347: return true
		348: return true
		349: return true
		352: return true
		35: return true
		115: return true
		_: return false

// In-body start-tag rule for an atom (see START_* uses).
fn body_start_class(atom: Int) Int:
	match atom:
		115: return 1  // html
		27: return 2  // base
		28: return 2  // basefont
		31: return 2  // bgsound
		143: return 2  // link
		161: return 2  // meta
		178: return 2  // noframes
		309: return 2  // script
		334: return 2  // style
		345: return 2  // template
		351: return 2  // title
		35: return 3  // body
		98: return 4  // frameset
		8: return 5  // address
		18: return 5  // article
		20: return 5  // aside
		34: return 5  // blockquote
		40: return 5  // center
		67: return 5  // details
		69: return 5  // dialog
		70: return 5  // dir
		73: return 5  // div
		74: return 5  // dl
		83: return 5  // fieldset
		84: return 5  // figcaption
		85: return 5  // figure
		87: return 5  // footer
		106: return 5  // header
		109: return 5  // hgroup
		148: return 5  // main
		159: return 5  // menu
		175: return 5  // nav
		184: return 5  // ol
		276: return 5  // p
		311: return 5  // search
		312: return 5  // section
		336: return 5  // summary
		359: return 5  // ul
		99: return 6  // h1
		100: return 6  // h2
		101: return 6  // h3
		102: return 6  // h4
		103: return 6  // h5
		104: return 6  // h6
		285: return 7  // pre
		145: return 7  // listing
		91: return 8  // form
		142: return 9  // li
		62: return 10  // dd
		78: return 10  // dt
		282: return 11  // plaintext
		37: return 12  // button
		1: return 13  // a
		26: return 14  // b
		32: return 14  // big
		46: return 14  // code
		79: return 14  // em
		86: return 14  // font
		117: return 14  // i
		304: return 14  // s
		319: return 14  // small
		332: return 14  // strike
		333: return 14  // strong
		355: return 14  // tt
		358: return 14  // u
		176: return 15  // nobr
		16: return 16  // applet
		153: return 16  // marquee
		183: return 16  // object
		341: return 17  // table
		17: return 18  // area
		36: return 18  // br
		80: return 18  // embed
		122: return 18  // img
		123: return 18  // input
		136: return 18  // keygen
		365: return 18  // wbr
		277: return 19  // param
		322: return 19  // source
		353: return 19  // track
		112: return 20  // hr
		121: return 21  // image
		346: return 22  // textarea
		369: return 23  // xmp
		120: return 24  // iframe
		177: return 25  // noembed
		181: return 26  // noscript
		313: return 27  // select
		272: return 28  // optgroup
		274: return 28  // option
		292: return 29  // rb
		302: return 29  // rtc
		300: return 30  // rp
		301: return 30  // rt
		154: return 31  // math
		338: return 31  // svg
		39: return 32  // caption
		47: return 32  // col
		48: return 32  // colgroup
		97: return 32  // frame
		105: return 32  // head
		343: return 32  // tbody
		344: return 32  // td
		347: return 32  // tfoot
		348: return 32  // th
		349: return 32  // thead
		352: return 32  // tr
		_: return 0

// In-body end-tag rule for an atom.
fn body_end_class(atom: Int) Int:
	match atom:
		35: return 1  // body
		115: return 2  // html
		8: return 3  // address
		18: return 3  // article
		20: return 3  // aside
		34: return 3  // blockquote
		37: return 3  // button
		40: return 3  // center
		67: return 3  // details
		69: return 3  // dialog
		70: return 3  // dir
		73: return 3  // div
		74: return 3  // dl
		83: return 3  // fieldset
		84: return 3  // figcaption
		85: return 3  // figure
		87: return 3  // footer
		106: return 3  // header
		109: return 3  // hgroup
		145: return 3  // listing
		148: return 3  // main
		159: return 3  // menu
		175: return 3  // nav
		184: return 3  // ol
		285: return 3  // pre
		311: return 3  // search
		312: return 3  // section
		336: return 3  // summary
		359: return 3  // ul
		91: return 4  // form
		276: return 5  // p
		142: return 6  // li
		62: return 7  // dd
		78: return 7  // dt
		99: return 8  // h1
		100: return 8  // h2
		101: return 8  // h3
		102: return 8  // h4
		103: return 8  // h5
		104: return 8  // h6
		1: return 9  // a
		26: return 9  // b
		32: return 9  // big
		46: return 9  // code
		79: return 9  // em
		86: return 9  // font
		117: return 9  // i
		176: return 9  // nobr
		304: return 9  // s
		319: return 9  // small
		332: return 9  // strike
		333: return 9  // strong
		355: return 9  // tt
		358: return 9  // u
		16: return 10  // applet
		153: return 10  // marquee
		183: return 10  // object
		36: return 11  // br
		345: return 12  // template
		_: return 0

fn svg_tag(name: String) String:
	match name:
		"altglyph": return "altGlyph"
		"altglyphdef": return "altGlyphDef"
		"altglyphitem": return "altGlyphItem"
		"animatecolor": return "animateColor"
		"animatemotion": return "animateMotion"
		"animatetransform": return "animateTransform"
		"clippath": return "clipPath"
		"feblend": return "feBlend"
		"fecolormatrix": return "feColorMatrix"
		"fecomponenttransfer": return "feComponentTransfer"
		"fecomposite": return "feComposite"
		"feconvolvematrix": return "feConvolveMatrix"
		"fediffuselighting": return "feDiffuseLighting"
		"fedisplacementmap": return "feDisplacementMap"
		"fedistantlight": return "feDistantLight"
		"feflood": return "feFlood"
		"fefunca": return "feFuncA"
		"fefuncb": return "feFuncB"
		"fefuncg": return "feFuncG"
		"fefuncr": return "feFuncR"
		"fegaussianblur": return "feGaussianBlur"
		"feimage": return "feImage"
		"femerge": return "feMerge"
		"femergenode": return "feMergeNode"
		"femorphology": return "feMorphology"
		"feoffset": return "feOffset"
		"fepointlight": return "fePointLight"
		"fespecularlighting": return "feSpecularLighting"
		"fespotlight": return "feSpotLight"
		"fetile": return "feTile"
		"feturbulence": return "feTurbulence"
		"foreignobject": return "foreignObject"
		"glyphref": return "glyphRef"
		"lineargradient": return "linearGradient"
		"radialgradient": return "radialGradient"
		"textpath": return "textPath"
		_: return ""

fn svg_attribute(name: String) String:
	match name:
		"attributename": return "attributeName"
		"attributetype": return "attributeType"
		"basefrequency": return "baseFrequency"
		"baseprofile": return "baseProfile"
		"calcmode": return "calcMode"
		"clippathunits": return "clipPathUnits"
		"diffuseconstant": return "diffuseConstant"
		"edgemode": return "edgeMode"
		"filterunits": return "filterUnits"
		"glyphref": return "glyphRef"
		"gradienttransform": return "gradientTransform"
		"gradientunits": return "gradientUnits"
		"kernelmatrix": return "kernelMatrix"
		"kernelunitlength": return "kernelUnitLength"
		"keypoints": return "keyPoints"
		"keysplines": return "keySplines"
		"keytimes": return "keyTimes"
		"lengthadjust": return "lengthAdjust"
		"limitingconeangle": return "limitingConeAngle"
		"markerheight": return "markerHeight"
		"markerunits": return "markerUnits"
		"markerwidth": return "markerWidth"
		"maskcontentunits": return "maskContentUnits"
		"maskunits": return "maskUnits"
		"numoctaves": return "numOctaves"
		"pathlength": return "pathLength"
		"patterncontentunits": return "patternContentUnits"
		"patterntransform": return "patternTransform"
		"patternunits": return "patternUnits"
		"pointsatx": return "pointsAtX"
		"pointsaty": return "pointsAtY"
		"pointsatz": return "pointsAtZ"
		"preservealpha": return "preserveAlpha"
		"preserveaspectratio": return "preserveAspectRatio"
		"primitiveunits": return "primitiveUnits"
		"refx": return "refX"
		"refy": return "refY"
		"repeatcount": return "repeatCount"
		"repeatdur": return "repeatDur"
		"requiredextensions": return "requiredExtensions"
		"requiredfeatures": return "requiredFeatures"
		"specularconstant": return "specularConstant"
		"specularexponent": return "specularExponent"
		"spreadmethod": return "spreadMethod"
		"startoffset": return "startOffset"
		"stddeviation": return "stdDeviation"
		"stitchtiles": return "stitchTiles"
		"surfacescale": return "surfaceScale"
		"systemlanguage": return "systemLanguage"
		"tablevalues": return "tableValues"
		"targetx": return "targetX"
		"targety": return "targetY"
		"textlength": return "textLength"
		"viewbox": return "viewBox"
		"viewtarget": return "viewTarget"
		"xchannelselector": return "xChannelSelector"
		"ychannelselector": return "yChannelSelector"
		"zoomandpan": return "zoomAndPan"
		_: return ""

// ---- public parse ----

fn limit_error() Error:
	return Error("HTML: limit exceeded", kind: "EOVERFLOW")

// A budget: none is unlimited and a negative bound is invalid.
fn budget(limit: Int?) Int!:
	if limit.is_none(): return ok(9223372036854775807)

	n := limit.get(0)
	if n < 0: return error(Error("HTML: invalid input", kind: "EINVAL"))

	return ok(n)

// Whether the tree under the document has at most `max_nodes` reachable nodes and nests
// at most
// `max_depth` levels (the document is level zero).
fn within_limits(p: Parser, max_depth: Int, max_nodes: Int) Bool:
	var stack: List[Int] = [1]
	var depths: List[Int] = [0]
	var count = 0

	while stack.length() > 0:
		id := stack.pop().get(1)
		depth := depths.pop().get(0)
		count += 1
		if count > max_nodes or depth > max_depth: return false

		var child = p.first[id]

		while child >= 0:
			stack.append(child)
			depths.append(depth + 1)
			child = p.next[child]

	return true

// Parses HTML into a normalized tree and applies the resource limits in `options`.
export fn parse(text: String, options: HtmlOptions = HtmlOptions()) HtmlNode!:
	max_bytes := budget(options.max_bytes)?
	max_depth := budget(options.max_depth)?
	max_nodes := budget(options.max_nodes)?
	if text.byte_length() > max_bytes: return error(limit_error())

	var max_open = max_depth
	if max_depth < 9000000000000000000: max_open = max_depth + 64

	src := text.to_bytes()
	var p = Parser(src: src.clone(), size: src.length(), max_open: max_open)
	p.run()
	if p.exceeded: return error(limit_error())
	if not within_limits(p, max_depth, max_nodes): return error(limit_error())

	return ok(node(p, 1))

// Copies node `id`, and everything under it, into an `HtmlNode`.
fn node(p: Parser, id: Int) HtmlNode:
	kind := p.kind[id]

	if kind == K_ELEMENT:
		var namespace = ""
		if p.ns[id] == NS_MATH: namespace = "math"
		if p.ns[id] == NS_SVG: namespace = "svg"
		return HtmlNode.Element(
			p.tag_name(id),
			namespace,
			attributes(p, id),
			children(p, id),
		)

	if kind == K_TEXT: return HtmlNode.Text(p.data[id].clone())
	if kind == K_COMMENT: return HtmlNode.Comment(p.data[id].clone())

	if kind == K_DOCTYPE:
		var public_id = ""
		var system_id = ""
		start := p.attr_start[id]

		for i in 0..p.attr_count[id]:
			if p.akey[start + i] == "public": public_id = p.aval[start + i].clone()
			if p.akey[start + i] == "system": system_id = p.aval[start + i].clone()

		return HtmlNode.Doctype(p.data[id].clone(), public_id, system_id)

	return HtmlNode.Document(children(p, id))

fn children(p: Parser, id: Int) List[HtmlNode]:
	var out: List[HtmlNode] = []
	var at = p.first[id]

	while at >= 0:
		out.append(node(p, at))
		at = p.next[at]

	return out

fn attributes(p: Parser, id: Int) List[HtmlAttribute]:
	var out: List[HtmlAttribute] = []
	start := p.attr_start[id]
	for i in 0..p.attr_count[id]:
		out.append(
			HtmlAttribute(
				name: p.akey[start + i].clone(),
				namespace: p.ans[start + i].clone(),
				value: p.aval[start + i].clone(),
			)
		)
	return out
