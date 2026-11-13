//! The strict parser, producing a [`Module`] or the first diagnostic.

use crate::ast::*;
use crate::diag::{Diagnostic, DiagnosticFix, Phase};
use crate::lexer::{PResult, lex};
use crate::pos::Pos;
use crate::symbol::{Names, Symbol};
use crate::token::{Tok, Token};
use std::sync::Arc;

/// Bounds recursive descent so hostile input produces a diagnostic instead of
/// exhausting the stack.
pub const MAX_NESTING: usize = 1000;
/// Bounds left-nested operator, member, call and index chains.
pub const MAX_CHAIN: usize = 10000;

const IMPL_REMOVED: &str = "'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it";
const TRY_REMOVED: &str = "'try' was replaced by a postfix '?': write f(x)? instead of try f(x), and x | step? instead of x | try step";

/// Parses `source` strictly. The first error aborts the parse.
pub fn parse(file: &Arc<str>, source: &str) -> PResult<Module> {
    let mut module = parse_chunk(file, source, 0, 0, 0)?;
    module.file = file.clone();
    module.source = Arc::from(source);
    Ok(module)
}

/// Parses a slice of a larger file whose first byte is at original offset
/// `base_offset` on line `base_line + 1`. Used by editor recovery.
pub(crate) fn parse_chunk(
    file: &Arc<str>,
    source: &str,
    base_offset: u32,
    base_line: u32,
    first_id: u32,
) -> PResult<Module> {
    let lexed = crate::lexer::lex_at(file, source, base_offset, base_line)?;
    let mut p = Parser::new(
        file,
        &lexed.source,
        lexed.tokens,
        &lexed.boundaries,
        0,
        0,
        first_id,
    );
    let mut module = Module::default();
    p.module(&mut module)?;
    module.node_count = p.next_id;
    Ok(module)
}

struct Parser<'a> {
    names: Names,
    file: &'a Arc<str>,
    src: &'a str,
    tokens: Vec<Token>,
    boundaries: &'a crate::lexer::ScanBoundaries,
    /// Start of `src` in the normalized source scanned by the outer lexer.
    source_origin: usize,
    at: usize,
    inline_statement: bool,
    inline_return: bool,
    block_lambda: bool,
    depth: usize,
    /// Bindings after the first of a `let (...)` group until `statements` collects them.
    queued: Vec<Stmt>,
    next_id: u32,
    /// While positive, failures are speculative: their messages are never shown.
    speculative: u32,
    /// One bit per token: set on a `[` whose bracketed tokens could all be type
    /// arguments. Computed in one pass, so an index is never tried as types.
    type_brackets: Vec<u64>,
}

/// Tokens that can appear between the brackets of type arguments.
fn type_token(kind: Tok) -> bool {
    matches!(
        kind,
        Tok::Name
            | Tok::Dot
            | Tok::LBracket
            | Tok::RBracket
            | Tok::Comma
            | Tok::Question
            | Tok::Bang
            | Tok::Fn
            | Tok::Var
            | Tok::LParen
            | Tok::RParen
    )
}

fn type_brackets(tokens: &[Token]) -> Vec<u64> {
    let mut bits = vec![0u64; tokens.len().div_ceil(64)];
    let mut open: Vec<(usize, bool)> = Vec::new();
    for (at, t) in tokens.iter().enumerate() {
        match t.kind {
            Tok::LBracket => open.push((at, true)),
            Tok::RBracket => {
                if let Some((from, ok)) = open.pop() {
                    if ok {
                        bits[from / 64] |= 1 << (from % 64);
                    }
                    if let Some(parent) = open.last_mut() {
                        parent.1 &= ok;
                    }
                }
            }
            kind if !type_token(kind) => {
                if let Some(top) = open.last_mut() {
                    top.1 = false;
                }
            }
            _ => {}
        }
    }
    bits
}

/// The position of byte `index` of a text token's source.
fn text_pos(pos: Pos, full: &str, index: usize, boundaries: &crate::lexer::ScanBoundaries) -> Pos {
    let before = &full[..index];
    let offset = (pos.offset as usize + index) as u32;
    let position = match before.rfind('\n') {
        None => Pos {
            line: pos.line,
            column: (pos.column as usize + index) as u32,
            offset,
        },
        Some(last) => Pos {
            line: pos.line + before.matches('\n').count() as u32,
            column: (index - last) as u32,
            offset,
        },
    };
    boundaries.restore_text_offset(pos, position)
}

/// Splits the text between multi-line delimiters into its content (without
/// the line break after the opening quotes and the closing line), the closing
/// line's indentation width, and the content's start within `body`.
fn multiline_body(body: &str) -> (&str, usize, usize) {
    let last = body.rfind('\n').unwrap_or(0);
    let indent = body.len() - last - 1;
    (&body[1.min(last)..last], indent, 1.min(last))
}

/// Removes up to `indent` leading blanks from every line of `content`.
fn dedent(content: &str, indent: usize) -> String {
    let mut out = String::with_capacity(content.len());
    for (i, line) in content.split('\n').enumerate() {
        if i > 0 {
            out.push('\n');
        }
        let blanks = line
            .bytes()
            .take(indent)
            .take_while(|b| matches!(b, b' ' | b'\t'))
            .count();
        out.push_str(&line[blanks..]);
    }
    out
}

fn describe(src: &str, t: Token) -> String {
    match t.kind {
        Tok::Newline => "end of line".into(),
        Tok::Indent => "an unexpected indented block".into(),
        Tok::Dedent => "the end of the block".into(),
        Tok::Eof => "end of file".into(),
        Tok::Name => format!("name '{}'", &src[t.lo as usize..t.hi as usize]),
        Tok::Number => format!("number {}", &src[t.lo as usize..t.hi as usize]),
        Tok::String => format!("text {}", &src[t.lo as usize..t.hi as usize]),
        k => format!("'{}'", k.as_str()),
    }
}

fn describe_kind(kind: &str) -> String {
    match kind {
        "NEWLINE" => "end of line".into(),
        "INDENT" => "an indented block".into(),
        "DEDENT" => "the end of the block".into(),
        "EOF" => "end of file".into(),
        "NAME" => "a name".into(),
        "NUMBER" => "a number".into(),
        "STRING" => "text in double quotes".into(),
        k => format!("'{}'", k),
    }
}

/// Adds the usual fix for the punctuation that is most often missing.
/// Text interpolates by default, so Python's `f"..."` prefix is a stray name.
const F_STRING_HINT: &str = "; there is no f-string prefix: text interpolates by default, so write \"...{value}...\" and escape literal braces as \\{ and \\}";

/// The unspellable name a destructuring `for` or lambda binds before its pattern.
const HIDDEN_ITEM: &str = "for item";

fn need_hint(kind: &str, found: Tok, found_text: &str) -> String {
    match kind {
        ":" => "; block headers (fn, if, else, for, while, match, type, enum, impl, test) end with ':' before their indented body".into(),
        ")" => "; close the parenthesis, separating items with commas".into(),
        "]" if found == Tok::For => {
            "; there are no comprehensions: build the list with map and filter, e.g. items.filter(fn x: x > 0).map(fn x: x * 2)".into()
        }
        "]" => "; close the bracket, separating items with commas".into(),
        "}" => "; close the brace, separating items with commas".into(),
        "(" if found == Tok::Lt => {
            "; type parameters use square brackets, e.g. fn identity[T](value: T) T:".into()
        }
        "(" => "; a call or parameter list starts with '('".into(),
        "from" => {
            if found == Tok::Comma {
                "; to import several names, write import a, b from \"path.ms\", or import (a from \"a.ms\", b from \"b.ms\") for several modules".into()
            } else {
                "; imports read: import name from \"path.ms\"".into()
            }
        }
        "in" => "; loops read: for item in items:".into(),
        "=" if found == Tok::Newline => {
            "; every let/var binding needs an initial value, e.g. var count: Int = 0".into()
        }
        "NAME" => {
            if found == Tok::SelfKw {
                "; 'self' is reserved: a method's receiver is implicit, so leave it out of the parameter list and write self.field in the body".into()
            } else if found == Tok::LParen {
                "; give it a name, e.g. fn add(a: Int, b: Int) Int:".into()
            } else if found_text == "_" {
                "; '_' is a reserved word and cannot be used as a name: loops, parameters and bindings need a real name such as item, unused or ignored".into()
            } else if found == Tok::Ref {
                "; 'ref' was removed: a function that returns part of a parameter returns a borrow of it, with no marker".into()
            } else if found.as_str() == found_text && found_text.starts_with(|c: char| c.is_ascii_alphabetic()) {
                format!("; '{}' is a reserved word and cannot be used as a name", found_text)
            } else {
                String::new()
            }
        }
        "NEWLINE" => "; end the statement with a line break".into(),
        "INDENT" => "; indent the block body by four spaces under its header".into(),
        _ => String::new(),
    }
}

/// Declaration words from other languages: the message and the Manuscript
/// spelling to replace the word with, when there is one.
fn foreign_declaration(t: Token, text: &str) -> Option<(String, Option<&'static str>)> {
    if t.kind == Tok::Var {
        return Some(("module level holds only constants (NAME := value); keep mutable state in a 'var' inside a fn, or in a field of a type".into(), None));
    }
    if t.kind != Tok::Name {
        return None;
    }
    let (replacement, advice) = match text {
        "function" | "def" | "func" | "fun" | "sub" => (
            Some("fn"),
            "declare a function as 'fn name(a: Int) Int:' with the result type after the parameters",
        ),
        "class" | "struct" | "record" | "data" => (
            Some("type"),
            "declare a type with 'type Name:' and 'field: Type' lines, then add methods as 'fn Name.method(...)' after it",
        ),
        "union" | "variant" | "sealed" => (
            Some("enum"),
            "declare an enum with 'enum Name:' and one 'Variant' or 'Variant(field: Type)' line each",
        ),
        "trait" | "protocol" | "abstract" => (
            Some("interface"),
            "declare a contract with 'interface Name:' and method signatures, then give a type methods that match it, 'fn Type.operation(...)'",
        ),
        "const" | "val" | "final" | "let" => (
            None,
            "write 'NAME := value' (or 'NAME: Type := value') for a module constant",
        ),
        "pub" | "public" => (
            Some("export"),
            "write 'export' before the declaration to make it visible to other modules",
        ),
        "use" | "require" | "include" | "using" | "from" => {
            (Some("import"), "imports read: import name from \"path.ms\"")
        }
        "static" | "private" | "internal" | "async" | "extern" | "package" | "namespace"
        | "module" => (
            None,
            "there is no such modifier; top level holds only import, let, fn, type, enum, interface, impl, and test, optionally prefixed by export",
        ),
        _ => return None,
    };
    Some((
        format!("'{text}' is not a Manuscript declaration keyword; {advice}"),
        replacement,
    ))
}

/// Precedence of `..`: above comparisons, below `+` and `-`.
const RANGE_LEVEL: u8 = 5;

fn binary_op(kind: Tok) -> Option<BinaryOp> {
    Some(match kind {
        Tok::Or => BinaryOp::Or,
        Tok::And => BinaryOp::And,
        Tok::EqEq => BinaryOp::Eq,
        Tok::NotEq => BinaryOp::Ne,
        Tok::Lt => BinaryOp::Lt,
        Tok::Gt => BinaryOp::Gt,
        Tok::Le => BinaryOp::Le,
        Tok::Ge => BinaryOp::Ge,
        Tok::Plus => BinaryOp::Add,
        Tok::Minus => BinaryOp::Sub,
        Tok::Star => BinaryOp::Mul,
        Tok::Slash => BinaryOp::Div,
        Tok::Percent => BinaryOp::Rem,
        _ => return None,
    })
}

fn starts_type(kind: Tok) -> bool {
    matches!(kind, Tok::Name | Tok::Fn | Tok::LParen)
}

fn arith_op(kind: Tok) -> Option<BinaryOp> {
    match kind {
        Tok::Plus | Tok::Minus | Tok::Star | Tok::Slash | Tok::Percent => binary_op(kind),
        _ => None,
    }
}

impl<'a> Parser<'a> {
    fn new(
        file: &'a Arc<str>,
        src: &'a str,
        tokens: Vec<Token>,
        boundaries: &'a crate::lexer::ScanBoundaries,
        source_origin: usize,
        depth: usize,
        next_id: u32,
    ) -> Parser<'a> {
        Parser {
            names: Names::global(),
            file,
            src,
            type_brackets: type_brackets(&tokens),
            tokens,
            boundaries,
            source_origin,
            at: 0,
            inline_statement: false,
            inline_return: false,
            block_lambda: false,
            depth,
            queued: Vec::new(),
            next_id,
            speculative: 0,
        }
    }

    fn id(&mut self) -> NodeId {
        let id = NodeId(self.next_id);
        self.next_id += 1;
        id
    }
    fn peek(&self) -> Token {
        self.tokens[self.at]
    }
    fn kind(&self) -> Tok {
        self.tokens[self.at].kind
    }
    /// Token `n` ahead of the current one, clamped to the final `Eof`.
    fn ahead(&self, n: usize) -> Token {
        self.tokens[(self.at + n).min(self.tokens.len() - 1)]
    }
    fn previous(&self) -> Token {
        self.tokens[self.at - 1]
    }
    fn text(&self, t: Token) -> &'a str {
        &self.src[t.lo as usize..t.hi as usize]
    }
    fn sym(&self, t: Token) -> Symbol {
        self.names.intern(self.text(t))
    }
    fn take(&mut self, k: Tok) -> bool {
        if self.kind() == k {
            self.at += 1;
            true
        } else {
            false
        }
    }
    fn next(&mut self) -> Token {
        let t = self.peek();
        self.at += 1;
        t
    }
    fn dummy(&self) -> Box<Diagnostic> {
        Box::new(Diagnostic::parse(self.file, Pos::default(), String::new()))
    }
    fn need(&mut self, k: Tok) -> PResult<Token> {
        let t = self.peek();
        if t.kind == k {
            self.at += 1;
            return Ok(t);
        }
        if self.speculative > 0 {
            return Err(self.dummy());
        }
        if k == Tok::Colon && t.kind == Tok::LBrace {
            return self.fail_fix(
                t,
                "expected ':', found '{'; blocks are not braced: end the header with ':', indent the body four spaces on the following lines, and remove the closing '}'",
                ":",
            );
        }
        let glued_f = t.kind == Tok::String
            && self.at > 0
            && self.text(self.previous()) == "f"
            && self.previous().end.offset == t.pos.offset;
        let hint = if glued_f {
            F_STRING_HINT.to_string()
        } else {
            need_hint(k.as_str(), t.kind, self.text(t))
        };
        let msg = format!(
            "expected {}, found {}{hint}",
            describe_kind(k.as_str()),
            describe(self.src, t),
        );
        self.fail(t, msg)
    }
    /// Consumes the contextual word `from` that ends an import's names.
    fn need_from(&mut self) -> PResult<()> {
        let t = self.peek();
        if t.kind == Tok::Name && self.text(t) == "from" {
            self.at += 1;
            return Ok(());
        }
        let msg = format!(
            "expected 'from', found {}{}",
            describe(self.src, t),
            need_hint("from", t.kind, self.text(t))
        );
        self.fail(t, msg)
    }
    fn fail<T>(&self, t: Token, message: impl Into<String>) -> PResult<T> {
        let mut d = Diagnostic::parse(self.file, t.pos, message);
        if t.end.line > 0 {
            d.end = Some(t.end);
        }
        Err(Box::new(d))
    }
    /// A legacy prefix, including the spaces before a following name on the
    /// same line. `case`, `case(...)`, and `case:` remain ordinary names.
    fn legacy_case_prefix(&self) -> Option<Token> {
        let mut prefix = self.peek();
        let next = self.ahead(1);
        if prefix.kind != Tok::Name
            || self.text(prefix) != "case"
            || next.kind != Tok::Name
            || prefix.pos.line != next.pos.line
        {
            return None;
        }
        prefix.end = next.pos;
        prefix.hi = next.lo;
        Some(prefix)
    }

    /// Fails on `t` with a machine-applicable replacement of exactly its range.
    fn fail_fix<T>(&self, t: Token, message: impl Into<String>, replacement: &str) -> PResult<T> {
        self.fail_fix_range(t, t, message, replacement)
    }
    /// Fails on `first` with a replacement of the range `first.pos..last.end`.
    fn fail_fix_range<T>(
        &self,
        first: Token,
        last: Token,
        message: impl Into<String>,
        replacement: &str,
    ) -> PResult<T> {
        let mut d = Diagnostic::parse(self.file, first.pos, message);
        if last.end.line > 0 {
            d.end = Some(last.end);
            d.fix = Some(DiagnosticFix {
                pos: first.pos,
                end: last.end,
                replacement: replacement.to_string(),
            });
        }
        Err(Box::new(d))
    }

    /// A symbolic operator can touch either operand; its word replacement
    /// needs separation wherever it would otherwise join an identifier/number.
    fn fail_word_operator<T>(
        &self,
        first: Token,
        last: Token,
        message: &str,
        word: &str,
    ) -> PResult<T> {
        let joins_word = |byte: &u8| byte.is_ascii_alphanumeric() || *byte == b'_';
        let bytes = self.src.as_bytes();
        let before = first
            .lo
            .checked_sub(1)
            .and_then(|at| bytes.get(at as usize));
        let after = bytes.get(last.hi as usize);
        let mut replacement = String::new();
        if before.is_some_and(joins_word) {
            replacement.push(' ');
        }
        replacement.push_str(word);
        if after.is_some_and(joins_word) {
            replacement.push(' ');
        }
        self.fail_fix_range(first, last, message, &replacement)
    }
    /// The colon after a parameter or field name; a missing one is usually a
    /// type written directly after the name.
    fn need_name_colon(&mut self, name: Token) -> PResult<()> {
        let t = self.peek();
        if t.kind == Tok::Name && self.speculative == 0 {
            let at = Token {
                pos: name.end,
                end: name.end,
                ..name
            };
            let msg = format!(
                "expected ':' between '{}' and its type; parameters and fields are written name: Type",
                self.text(name)
            );
            return self.fail_fix(at, msg, ":");
        }
        self.need(Tok::Colon).map(|_| ())
    }
    fn newlines(&mut self) {
        while self.take(Tok::Newline) {}
    }
    fn link(&mut self, links: &mut usize) -> PResult<()> {
        *links += 1;
        if *links > MAX_CHAIN {
            let t = self.peek();
            return self.fail(
                t,
                format!(
                    "expression chain exceeds {} operators or accesses; split it into named parts",
                    MAX_CHAIN
                ),
            );
        }
        Ok(())
    }
    /// Counts one level of nesting; on success the caller must decrement `depth`.
    fn enter(&mut self) -> PResult<()> {
        self.depth += 1;
        if self.depth > MAX_NESTING {
            if self.speculative > 0 {
                return Err(self.dummy());
            }
            let t = self.peek();
            return self.fail(t, format!("nesting exceeds {} levels; split the expression, type, or block into named parts", MAX_NESTING));
        }
        Ok(())
    }

    fn end(&mut self) -> PResult<()> {
        if self.inline_statement {
            match self.kind() {
                Tok::Newline | Tok::Comma | Tok::RParen | Tok::RBracket | Tok::RBrace => {
                    return Ok(());
                }
                _ => {}
            }
            let t = self.peek();
            let msg = format!(
                "expected end of inline statement, found {}; an inline body holds one simple statement, so move more statements to an indented block",
                describe(self.src, t)
            );
            return self.fail(t, msg);
        }
        if self.take(Tok::Newline) {
            self.newlines();
            return Ok(());
        }
        if self.at > 0 && self.previous().kind == Tok::Dedent {
            return Ok(());
        }
        let t = self.peek();
        if self.block_lambda && t.kind == Tok::Comma {
            return self.fail(t, "a comma cannot end a statement in an indented function body; to separate enclosing arguments, put the comma on its own line dedented to the fn header, or group the function in parentheses");
        }
        if t.kind == Tok::Amp {
            return self.and_and(t);
        }
        if t.kind == Tok::Arrow || (t.kind == Tok::Assign && self.ahead(1).kind == Tok::Gt) {
            return self.fail(
                t,
                "there is no arrow function; anonymous functions are written fn x: x + 1",
            );
        }
        let prev_new = self.at > 0 && self.text(self.previous()) == "new";
        let prev_word = if self.at > 0 {
            self.text(self.previous())
        } else {
            ""
        };
        let glued_text =
            t.kind == Tok::String && self.at > 0 && self.previous().end.offset == t.pos.offset;
        let hint = match t.kind {
            _ if prev_word == "def" && t.kind == Tok::Name => {
                "; there is no 'def': declare a function with 'fn name(a: Int) Int:'"
            }
            _ if prev_word == "lambda" => {
                "; there is no 'lambda': write an anonymous function as 'fn x: x + 1'"
            }
            _ if prev_word == "elif" => {
                "; there is no 'elif': write 'else if <condition>:' for a further branch"
            }
            _ if prev_word == "f" && glued_text => F_STRING_HINT,
            Tok::Name if self.text(t) == "is" => {
                "; there is no 'is' operator: write '==' to compare values, or 'match value:' to test which alternative a value is"
            }
            Tok::Name if prev_new => {
                "; there is no 'new': construct a value by calling the type, Name(field: value)"
            }
            Tok::If => {
                "; there is no inline conditional expression 'a if c else b': write 'if c: a else: b', or use an if statement"
            }
            Tok::Question => {
                "; '?' after a Result call propagates its error, and is not '??' or 'c ? a : b': unwrap an Optional with 'if x := v:' or give it a default with 'v.get(default)', chain with 'a?.b', and write a conditional as 'if c: a else: b'"
            }
            Tok::Comma => {
                "; commas separate items only inside (), [] or {}: put each field, case, or statement on its own line"
            }
            Tok::LBrace => {
                "; '{' does not open a block: end the header with ':' and indent the body (an interface method is just its signature)"
            }
            _ => {
                "; put one statement per line, and join operands with an operator or a comma inside brackets"
            }
        };
        let msg = format!(
            "expected end of statement, found {}{hint}",
            describe(self.src, t)
        );
        self.fail(t, msg)
    }

    // ---- module ----

    fn module(&mut self, module: &mut Module) -> PResult<()> {
        while self.kind() != Tok::Eof {
            self.newlines();
            if self.kind() == Tok::Eof {
                break;
            }
            if self.take(Tok::Import) {
                self.import(module)?;
                continue;
            }
            if self.kind() == Tok::Name
                && self.text(self.peek()) == "from"
                && self.ahead(1).kind == Tok::String
            {
                let t = self.peek();
                return self.fail(t, "imports read: import name, other from \"path.ms\"");
            }
            let exported = self.take(Tok::Export);
            let mut d = self.declaration()?;
            if exported && matches!(d.kind, DeclKind::Impl(_) | DeclKind::Test(_)) {
                let t = self.previous();
                return self.fail(t, "only types, interfaces, and named functions can be exported; remove 'export' before this impl, test, or bench");
            }
            d.export = exported;
            module.decls.push(d);
        }
        Ok(())
    }

    /// Parses the rest of an import after `import`: `a, b from "path"`,
    /// `(a, b) from "path"`, or a group of clauses
    /// `(a, b from "path", c from "other")`.
    fn import(&mut self, module: &mut Module) -> PResult<()> {
        let pos = self.previous().pos;
        if self.kind() == Tok::Star {
            let t = self.peek();
            return self.fail(t, "namespace and wildcard imports are unsupported; import individual exports with 'import Name, OtherName from \"./module.ms\"'");
        }
        if self.kind() == Tok::LBrace {
            let t = self.peek();
            return self.fail(t, "imports take no braces; write 'import a, b from \"path.ms\"', or 'import (a, b) from \"path.ms\"' to wrap across lines");
        }
        // A bare list is comma-separated on one line; a parenthesized list
        // wraps across lines and permits a trailing comma. Both are nonempty.
        // Inside parentheses, `from` after the names starts a clause, so one
        // statement can import from several modules.
        let wrapped = self.take(Tok::LParen);
        loop {
            let names = self.import_names(wrapped)?;
            if wrapped && self.kind() == Tok::RParen {
                self.need(Tok::RParen)?;
                self.need_from()?;
                let path = self.import_path()?;
                self.push_imports(module, pos, names, &path);
                break;
            }
            self.need_from()?;
            let path = self.import_path()?;
            self.push_imports(module, pos, names, &path);
            if !wrapped {
                break;
            }
            if !self.take(Tok::Comma) || self.kind() == Tok::RParen {
                self.need(Tok::RParen)?;
                break;
            }
        }
        self.end()
    }

    fn import_names(&mut self, wrapped: bool) -> PResult<Vec<Token>> {
        let mut names = Vec::new();
        loop {
            names.push(self.need(Tok::Name)?);
            if self.kind() == Tok::Name && self.text(self.peek()) == "as" {
                let t = self.peek();
                return self.fail(t, "imports cannot be renamed with 'as'; import the name as the module declares it");
            }
            if !self.take(Tok::Comma) || (wrapped && self.kind() == Tok::RParen) {
                return Ok(names);
            }
        }
    }

    fn import_path(&mut self) -> PResult<Box<str>> {
        let token = self.need(Tok::String)?;
        self.single_line(token, "import paths")?;
        let mut parts = self.text_parts_of(token)?;
        match (parts.len(), parts.pop()) {
            (1, Some(TextPart::Lit(text))) => Ok(text),
            _ => self.fail(
                token,
                "import paths cannot interpolate; write the path as plain text without {…}",
            ),
        }
    }

    fn push_imports(&mut self, module: &mut Module, pos: Pos, names: Vec<Token>, path: &str) {
        let clause = names[0].pos;
        for name in names {
            let id = self.id();
            module.imports.push(Import {
                id,
                pos,
                clause,
                name_pos: name.pos,
                name: self.sym(name),
                path: path.into(),
            });
        }
    }

    // ---- types ----

    fn type_params(&mut self) -> PResult<Vec<TypeParam>> {
        let mut result = Vec::new();
        if !self.take(Tok::LBracket) {
            return Ok(result);
        }
        loop {
            let name = self.need(Tok::Name)?;
            let mut bounds = Vec::new();
            let mut default = None;
            if self.take(Tok::Colon) {
                bounds.push(self.named_type()?);
                while self.take(Tok::Amp) {
                    bounds.push(self.named_type()?);
                }
                if matches!(self.kind(), Tok::Plus | Tok::And) {
                    let t = self.peek();
                    return self.fail_fix(
                        t,
                        "combine bounds with '&', as in T: Comparable & Clonable",
                        "&",
                    );
                }
            }
            if self.take(Tok::Assign) {
                default = Some(self.typ()?);
            }
            let id = self.id();
            result.push(TypeParam {
                id,
                pos: name.pos,
                name: self.sym(name),
                bounds,
                default,
            });
            if !self.take(Tok::Comma) {
                break;
            }
            if self.kind() == Tok::RBracket {
                break;
            }
        }
        self.need(Tok::RBracket)?;
        Ok(result)
    }

    fn parameters(&mut self, defaults: bool, inferred: bool) -> PResult<Vec<Param>> {
        self.need(Tok::LParen)?;
        let mut params = Vec::new();
        if !self.take(Tok::RParen) {
            loop {
                let mutable = self.take(Tok::Var);
                let name = self.need(Tok::Name)?;
                let mut ty = None;
                let mut default = None;
                if self.take(Tok::Colon) {
                    if self.kind() == Tok::Var {
                        let t = self.peek();
                        let msg = format!(
                            "'var' goes before the parameter name, not its type; write var {}: Type",
                            self.text(name)
                        );
                        return self.fail(t, msg);
                    }
                    ty = Some(self.typ()?);
                } else if !inferred || self.kind() == Tok::Name {
                    self.need_name_colon(name)?;
                }
                if self.take(Tok::Assign) {
                    if !defaults {
                        let t = self.previous();
                        return self.fail(t, "function types and case payloads cannot have defaults; put the default on a named function parameter or a type field instead");
                    }
                    default = Some(self.expression(0)?);
                } else if defaults && let Some(t) = &ty {
                    default = self.implicit_none(t);
                }
                let id = self.id();
                params.push(Param {
                    id,
                    pos: name.pos,
                    name: self.sym(name),
                    ty,
                    default,
                    mutable,
                });
                if !self.take(Tok::Comma) {
                    break;
                }
                if self.kind() == Tok::RParen {
                    break;
                }
            }
            self.need(Tok::RParen)?;
        }
        Ok(params)
    }

    /// The default of a `T?` parameter or field written without one: `none`.
    fn implicit_none(&mut self, t: &TypeRef) -> Option<Expr> {
        let TypeKind::Named { name, args } = &t.kind else {
            return None;
        };
        (self.names.str(*name) == "Optional" && args.len() == 1)
            .then(|| self.mk(t.pos, ExprKind::Name(self.names.intern("none"))))
    }

    fn named_type(&mut self) -> PResult<TypeRef> {
        let name = self.need(Tok::Name)?;
        let mut full = self.sym(name);
        if self.kind() == Tok::Dot {
            let mut s = String::from(self.names.str(full));
            while self.take(Tok::Dot) {
                s.push('.');
                let part = self.need(Tok::Name)?;
                s.push_str(self.text(part));
            }
            full = self.names.intern(&s);
        }
        let mut args = Vec::new();
        if self.kind() == Tok::LBracket
            && self.speculative == 0
            && self.names.str(full) == "Callable"
        {
            let t = self.peek();
            return self.fail(t, format!("there is no {full_t}[...] type; a function type is written fn(Int) Int: parameter types in parentheses, then the result type", full_t = self.names.str(full)));
        }
        if self.kind() == Tok::LBracket
            && self.speculative == 0
            && self.names.str(full) == "Optional"
        {
            let t = self.peek();
            return self.fail(
                t,
                "there is no Optional[T] spelling; write T? instead, e.g. Int? or (fn(Int) Int)?",
            );
        }
        if self.take(Tok::LBracket) {
            if self.speculative > 0 && !self.type_bracket(self.at - 1) {
                return Err(self.dummy());
            }
            args = self.type_args()?;
        }
        let lt = self.peek();
        if lt.kind == Tok::Lt
            && self.speculative == 0
            && lt.pos.offset == self.previous().end.offset
            && args.is_empty()
        {
            return self.fail(lt, format!("type arguments use square brackets, not angle brackets; write {full_t}[T] instead of {full_t}<T>", full_t = self.names.str(full)));
        }
        let id = self.id();
        Ok(TypeRef {
            id,
            pos: name.pos,
            kind: TypeKind::Named { name: full, args },
        })
    }

    /// Whether the `[` at token `at` encloses only tokens a type can contain.
    fn type_bracket(&self, at: usize) -> bool {
        self.type_brackets[at / 64] >> (at % 64) & 1 == 1
    }

    fn type_args(&mut self) -> PResult<Vec<TypeRef>> {
        let mut types = Vec::new();
        loop {
            types.push(self.typ()?);
            if !self.take(Tok::Comma) {
                break;
            }
            if self.kind() == Tok::RBracket {
                break;
            }
        }
        self.need(Tok::RBracket)?;
        Ok(types)
    }

    /// Parses the type that follows a parameter list, rejecting the removed
    /// `->` and a missing type with the form to write instead.
    fn result_type(&mut self) -> PResult<TypeRef> {
        let t = self.peek();
        if t.kind == Tok::Arrow {
            return self.fail_fix(
                t,
                "result types follow the parameter list without an arrow; remove '->', e.g. fn f() Unit:",
                "",
            );
        }
        if t.kind == Tok::Colon || t.kind == Tok::Newline {
            if self.speculative > 0 {
                return Err(self.dummy());
            }
            return self.fail(
                t,
                "every fn declares its result type after the parameter list, e.g. fn f() Unit:",
            );
        }
        self.no_ref()?;
        self.typ()
    }

    /// Wraps `t` once per trailing suffix, left to right: `T?` is `Optional[T]`, `T!` is
    /// `Result[T, Error]`, and `T!E` (E directly after the bang) is `Result[T, E]`. A function
    /// type needs parentheses first, since its result type takes the suffix.
    fn type_suffix(&mut self, mut t: TypeRef) -> PResult<TypeRef> {
        loop {
            let pos = t.pos;
            let (name, args) = if self.take(Tok::Question) {
                ("Optional", vec![t])
            } else if self.take(Tok::Bang) {
                let bang = self.previous();
                let next = self.peek();
                let error = if next.kind == Tok::Name && next.lo == bang.hi {
                    self.named_type()?
                } else {
                    let id = self.id();
                    TypeRef {
                        id,
                        pos,
                        kind: TypeKind::Named {
                            name: self.names.intern("Error"),
                            args: Vec::new(),
                        },
                    }
                };
                ("Result", vec![t, error])
            } else {
                return Ok(t);
            };
            let id = self.id();
            t = TypeRef {
                id,
                pos,
                kind: TypeKind::Named {
                    name: self.names.intern(name),
                    args,
                },
            };
        }
    }

    fn typ(&mut self) -> PResult<TypeRef> {
        self.enter()?;
        let r = self.typ_inner();
        self.depth -= 1;
        r
    }

    fn typ_inner(&mut self) -> PResult<TypeRef> {
        let first = self.peek();
        if first.kind == Tok::Fn {
            self.at += 1;
            self.need(Tok::LParen)?;
            let mut params = Vec::new();
            if !self.take(Tok::RParen) {
                loop {
                    // `fn(var List[Int]) Unit`: a parameter the function changes in place.
                    let mutable = self.take(Tok::Var);
                    let ty = self.typ()?;
                    let id = self.id();
                    params.push(Param {
                        id,
                        pos: ty.pos,
                        name: self.names.intern(&format!("_{}", params.len())),
                        ty: Some(ty),
                        default: None,
                        mutable,
                    });
                    if !self.take(Tok::Comma) {
                        break;
                    }
                    if self.kind() == Tok::RParen {
                        break;
                    }
                }
                self.need(Tok::RParen)?;
            }
            let result = Box::new(self.typ()?);
            let id = self.id();
            return Ok(TypeRef {
                id,
                pos: first.pos,
                kind: TypeKind::Fn { params, result },
            });
        }
        let t = if self.take(Tok::LParen) {
            let t = self.typ()?;
            self.need(Tok::RParen)?;
            t
        } else {
            self.named_type()?
        };
        self.type_suffix(t)
    }

    // ---- declarations ----

    /// Parses a module constant: `name := value` or `name: Type := value`.
    fn constant(&mut self) -> PResult<ConstDecl> {
        let name = self.need(Tok::Name)?;
        let mut ty = None;
        if self.take(Tok::Colon) {
            ty = Some(self.typ()?);
        }
        self.need_immutable_bind()?;
        // A binary expression's position is its operator, so the statement
        // starts at the first token of the initializer for source tooling.
        let init_pos = self.peek().pos;
        let value = self.expression(0)?;
        Ok(ConstDecl {
            name: self.sym(name),
            ty,
            value,
            init_pos,
        })
    }

    /// Parses the `( ... )` after a consumed `let` or `var`. The lexer ends
    /// each line of the group with a newline; `entry` parses one binding at the
    /// start of its line.
    fn binding_group(
        &mut self,
        keyword: Token,
        entry: &mut dyn FnMut(&mut Parser<'a>) -> PResult<()>,
    ) -> PResult<()> {
        let mut indent = keyword.pos.column;
        let mut i = self.at as isize - 2;
        while i >= 0
            && self.tokens[i as usize].pos.line == keyword.pos.line
            && self.tokens[i as usize].kind != Tok::Newline
        {
            indent = self.tokens[i as usize].pos.column;
            i -= 1;
        }
        let kw = keyword.kind.as_str();
        if self.inline_statement {
            let t = self.peek();
            return self.fail(t, format!("a binding group needs its own lines; put '{kw} (' on a line of its own with one binding per indented line, or write single '{kw} name = value' bindings"));
        }
        self.need(Tok::LParen)?;
        if self.kind() != Tok::Newline {
            let t = self.peek();
            return self.fail(t, format!("a binding group starts its entries on the next line; write '{kw} (' then one 'name = value' per indented line, or destructure with '{kw} [a, b] = value' or '{kw} {{x, y}} = value'"));
        }
        self.next();
        let mut count = 0;
        loop {
            self.newlines();
            let t = self.peek();
            if t.kind == Tok::RParen {
                if t.pos.column != indent {
                    return self.fail(t, format!("the closing ')' of a binding group aligns with its '{kw}' line, at column {indent}"));
                }
                break;
            } else if t.kind == Tok::Eof {
                self.need(Tok::RParen)?;
            } else if t.pos.column != indent + 4 {
                return self.fail(t, format!("binding group entries are indented four spaces past the '{kw}' line, to column {}", indent + 4));
            }
            entry(self)?;
            count += 1;
            if self.kind() == Tok::Comma {
                let t = self.peek();
                return self.fail(t, format!("a binding group holds one 'name = value' per line, not a comma list; to destructure write '{kw} [a, b] = value' or '{kw} {{x, y}} = value'"));
            }
            // A block lambda value ends at its dedent, which also ends the line.
            if self.previous().kind != Tok::Dedent {
                self.need(Tok::Newline)?;
            }
        }
        if count == 0 {
            let t = self.peek();
            return self.fail(
                t,
                "a binding group cannot be empty; add 'name = value' lines or remove the group",
            );
        }
        self.need(Tok::RParen)?;
        self.end()
    }

    fn method_signature(
        &mut self,
        name: Token,
        generics: bool,
        body: bool,
        mutating: bool,
    ) -> PResult<Method> {
        let type_params = if generics {
            self.type_params()?
        } else {
            Vec::new()
        };
        let params = self.parameters(true, false)?;
        let result = self.result_type()?;
        let body = if body {
            self.statement_suite(false, true)?
        } else {
            Vec::new()
        };
        let id = self.id();
        Ok(Method {
            id,
            pos: name.pos,
            func: Func {
                name: self.sym(name),
                type_params,
                params,
                result,
                body,
                external: false,
            },
            mutating,
        })
    }

    /// Parses the rest of `test "name":` or `bench "name":` after the keyword.
    fn test_block(&mut self, bench: bool) -> PResult<DeclKind> {
        let name = self.need(Tok::String)?;
        self.single_line(name, if bench { "bench names" } else { "test names" })?;
        let mut parts = self.text_parts_of(name)?;
        let text = match (parts.len(), parts.pop()) {
            (1, Some(TextPart::Lit(text))) => text,
            _ if bench => {
                return self.fail(
                    name,
                    "bench names cannot interpolate; use plain text, e.g. bench \"sums a list\":",
                );
            }
            _ => {
                return self.fail(
                    name,
                    "test names cannot interpolate; use plain text, e.g. test \"adds numbers\":",
                );
            }
        };
        let mut per = 1;
        if bench && self.kind() == Tok::Name && self.text(self.peek()) == "per" {
            self.at += 1;
            let count = self.need(Tok::Number)?;
            per = match self.text(count).parse::<i64>() {
                Ok(n) if n > 0 => n,
                _ => {
                    return self.fail(
                        count,
                        "'per' takes a positive whole number of operations, e.g. bench \"sums a list\" per 1000:",
                    );
                }
            };
        }
        let body = self.suite()?;
        Ok(DeclKind::Test(TestDecl {
            name: text,
            body,
            bench,
            per,
        }))
    }

    fn declaration(&mut self) -> PResult<Decl> {
        let token = self.peek();
        let mut export_pos_dummy = ();
        let _ = &mut export_pos_dummy;
        let kind = match token.kind {
            Tok::Fn if self.receiver_method_ahead() => {
                // `fn [var] Type[T].name(...)`: one method of `Type`, the same declaration as a
                // one-method `impl Type:` block.
                self.at += 1;
                let mutating = self.take(Tok::Var);
                // The receiver is a plain name with optional arguments: `named_type` would read
                // `Type.name` as a module-qualified type.
                let receiver_name = self.need(Tok::Name)?;
                // `[T: Bound]` names the receiver's arguments and bounds them in one list.
                let bounded = self.kind() == Tok::LBracket
                    && self.ahead(1).kind == Tok::Name
                    && self.ahead(2).kind == Tok::Colon;
                let mut bounds = Vec::new();
                let args = if bounded {
                    bounds = self.type_params()?;
                    bounds
                        .iter()
                        .map(|p| TypeRef {
                            id: self.id(),
                            pos: p.pos,
                            kind: TypeKind::Named {
                                name: p.name,
                                args: Vec::new(),
                            },
                        })
                        .collect()
                } else if self.take(Tok::LBracket) {
                    self.type_args()?
                } else {
                    Vec::new()
                };
                let receiver = TypeRef {
                    id: self.id(),
                    pos: receiver_name.pos,
                    kind: TypeKind::Named {
                        name: self.sym(receiver_name),
                        args,
                    },
                };
                self.need(Tok::Dot)?;
                let name = self.need(Tok::Name)?;
                let method = self.method_signature(name, true, true, mutating)?;
                DeclKind::Impl(ImplDecl {
                    contract: None,
                    receiver,
                    bounds,
                    methods: vec![method],
                })
            }
            Tok::Fn => {
                self.at += 1;
                let name = self.need(Tok::Name)?;
                let type_params = self.type_params()?;
                let params = self.parameters(true, false)?;
                let result = self.result_type()?;
                let body = self.statement_suite(false, true)?;
                DeclKind::Fn(Func {
                    name: self.sym(name),
                    type_params,
                    params,
                    result,
                    body,
                    external: false,
                })
            }
            Tok::Extern if self.ahead(1).kind == Tok::Type => {
                self.at += 1;
                self.at += 1;
                let name_tok = self.need(Tok::Name)?;
                let name = self.sym(name_tok);
                let type_params = self.type_params()?;
                if self.kind() == Tok::Colon {
                    let t = self.peek();
                    return self.fail(t, "an extern type has no body; remove the ':'");
                }
                self.end()?;
                DeclKind::Type(TypeDecl {
                    name,
                    type_params,
                    fields: Vec::new(),
                    external: true,
                    opaque: false,
                })
            }
            Tok::Extern => {
                self.at += 1;
                self.need(Tok::Fn)?;
                let name = self.need(Tok::Name)?;
                let type_params = self.type_params()?;
                let params = self.parameters(true, false)?;
                let result = self.result_type()?;
                if self.kind() == Tok::Colon {
                    let t = self.peek();
                    return self.fail(t, "an extern fn has no body; remove the ':'");
                }
                self.end()?;
                DeclKind::Fn(Func {
                    name: self.sym(name),
                    type_params,
                    params,
                    result,
                    body: Vec::new(),
                    external: true,
                })
            }
            Tok::Name if matches!(self.ahead(1).kind, Tok::ColonAssign | Tok::Colon) => {
                let c = self.constant()?;
                self.end()?;
                DeclKind::Const(c)
            }
            Tok::Test => {
                self.at += 1;
                self.test_block(false)?
            }
            Tok::Name if self.text(token) == "bench" && self.ahead(1).kind == Tok::String => {
                self.at += 1;
                self.test_block(true)?
            }
            Tok::Impl => return self.fail(token, IMPL_REMOVED),
            Tok::Type | Tok::Enum | Tok::Interface => return self.type_declaration(token),
            Tok::Name
                if self.text(token) == "opaque"
                    && matches!(self.ahead(1).kind, Tok::Type | Tok::Enum) =>
            {
                self.at += 1;
                let next = self.peek();
                let mut decl = self.type_declaration(next)?;
                decl.pos = token.pos;
                match &mut decl.kind {
                    DeclKind::Type(r) => r.opaque = true,
                    DeclKind::Alternative(a) => a.opaque = true,
                    _ => {}
                }
                return Ok(decl);
            }
            _ => {
                if let Some((msg, replacement)) = foreign_declaration(token, self.text(token)) {
                    return match replacement {
                        Some(r) => self.fail_fix(token, msg, r),
                        None => self.fail(token, msg),
                    };
                }
                if token.kind == Tok::Export {
                    return self.fail_fix(
                        token,
                        "'export' appears twice; write it once before the declaration",
                        "",
                    );
                }
                if token.kind == Tok::Name && self.text(token) == "opaque" {
                    let advice = if self.ahead(1).kind == Tok::Export {
                        let keyword = if self.ahead(2).kind == Tok::Enum {
                            "enum"
                        } else {
                            "type"
                        };
                        format!("write 'export opaque {keyword} Name:', with export first")
                    } else {
                        "'opaque' applies only to a type or enum; write 'opaque type Name:' or 'opaque enum Name:', optionally after 'export'".into()
                    };
                    return self.fail(token, format!("misplaced 'opaque'; {advice}"));
                }
                let msg = format!(
                    "expected a module declaration or import, found {}; top level holds only import, constants (NAME := value), fn, type, enum, interface, impl, and test (optionally prefixed by export), so put statements inside a fn",
                    describe(self.src, token)
                );
                return self.fail(token, msg);
            }
        };
        let id = self.id();
        Ok(Decl {
            id,
            pos: token.pos,
            export: false,
            synthetic: false,
            kind,
        })
    }

    /// Whether the `fn` at the cursor starts a receiver method (`fn [var] Type[T].name`): a name,
    /// optionally followed by a balanced `[...]`, then `.`. A plain `fn name[T](...)` has `(` there.
    fn receiver_method_ahead(&self) -> bool {
        let mut at = 1;
        if self.ahead(at).kind == Tok::Var {
            at += 1;
        }
        if self.ahead(at).kind != Tok::Name {
            return false;
        }
        at += 1;
        if self.ahead(at).kind == Tok::LBracket {
            let mut depth = 0usize;
            loop {
                match self.ahead(at).kind {
                    Tok::LBracket => depth += 1,
                    Tok::RBracket => {
                        depth -= 1;
                        if depth == 0 {
                            at += 1;
                            break;
                        }
                    }
                    Tok::Newline | Tok::Eof => return false,
                    _ => {}
                }
                at += 1;
            }
        }
        self.ahead(at).kind == Tok::Dot
    }

    fn type_declaration(&mut self, token: Token) -> PResult<Decl> {
        self.at += 1;
        let name_tok = self.need(Tok::Name)?;
        let name = self.sym(name_tok);
        let type_params = self.type_params()?;
        if token.kind == Tok::Type && self.take(Tok::Assign) {
            let mut targets = vec![self.typ()?];
            while self.take(Tok::Pipe) {
                targets.push(self.typ()?);
            }
            self.end()?;
            let id = self.id();
            return Ok(Decl {
                id,
                pos: token.pos,
                export: false,
                synthetic: false,
                kind: DeclKind::Alias(AliasDecl {
                    name,
                    type_params,
                    targets,
                }),
            });
        }
        self.need(Tok::Colon)?;
        if token.kind == Tok::Interface && self.take(Tok::Ellipsis) {
            // `interface Name: ...` declares a property with no operations, like `Data`.
            self.end()?;
            let id = self.id();
            return Ok(Decl {
                id,
                pos: token.pos,
                export: false,
                synthetic: false,
                kind: DeclKind::Interface(InterfaceDecl {
                    name,
                    type_params,
                    methods: Vec::new(),
                }),
            });
        }
        if token.kind == Tok::Type && self.take(Tok::Ellipsis) {
            self.end()?;
            let id = self.id();
            return Ok(Decl {
                id,
                pos: token.pos,
                export: false,
                synthetic: false,
                kind: DeclKind::Type(TypeDecl {
                    name,
                    type_params,
                    fields: Vec::new(),
                    external: false,
                    opaque: false,
                }),
            });
        }
        if token.kind == Tok::Enum && self.kind() == Tok::Ellipsis {
            return self.fail(self.peek(), "an enum must declare at least one variant; replace '...' with 'Name' or 'Name(field: Type)'");
        }
        self.need(Tok::Newline)?;
        if token.kind == Tok::Enum && self.kind() != Tok::Indent {
            return self.fail(self.peek(), "an enum must declare at least one variant; indent 'Name' or 'Name(field: Type)' under the header");
        }
        self.need(Tok::Indent)?;
        let mut fields: Vec<Param> = Vec::new();
        let mut cases: Vec<Case> = Vec::new();
        let mut methods: Vec<Method> = Vec::new();
        while self.kind() != Tok::Dedent {
            self.newlines();
            if self.kind() == Tok::Dedent {
                break;
            }
            if token.kind == Tok::Type
                && (self.legacy_case_prefix().is_some()
                    || (self.kind() == Tok::Name
                        && matches!(
                            self.ahead(1).kind,
                            Tok::LParen | Tok::Newline | Tok::Dedent | Tok::Eof
                        )))
            {
                return self.fail(token, "a type declared with 'type' cannot contain enum variants; replace 'type' with 'enum' and remove any legacy 'case' prefixes");
            }
            if token.kind == Tok::Enum {
                if let Some(prefix) = self.legacy_case_prefix() {
                    return self.fail(prefix, "enum variants do not use 'case'; remove the prefix and write 'Name' or 'Name(field: Type)'");
                }
                if self.kind() != Tok::Name {
                    return self.fail(self.peek(), "an enum contains only variants; write 'Name' or 'Name(field: Type)', use 'type' for type fields, and put methods in an 'impl' block");
                }
            }
            if token.kind == Tok::Interface && !matches!(self.kind(), Tok::Fn | Tok::Var) {
                let t = self.peek();
                return self.fail(t, "an interface contains only operation signatures; write 'fn name(...) Type' and put method bodies in an 'impl' block");
            }
            if token.kind == Tok::Enum {
                let name = self.need(Tok::Name)?;
                let mut payload = Vec::new();
                if self.kind() == Tok::LParen {
                    payload = self.parameters(false, false)?;
                    if payload.iter().any(|p| p.mutable) {
                        let t = self.previous();
                        return self.fail(t, "case payload fields cannot be 'var'; mutability belongs to the binding that holds the value");
                    }
                    if payload.is_empty() {
                        let n = self.text(name);
                        return self.fail(name, format!("payloadless variants omit parentheses; write '{n}' instead of '{n}()'"));
                    }
                }
                if self.kind() == Tok::Colon {
                    return self.fail(self.peek(), "enum variants have no field or method bodies; write 'Name' or 'Name(field: Type)', use 'type' for type fields, and put methods in an 'impl' block");
                }
                if self.kind() == Tok::Assign {
                    return self.fail(self.peek(), "enum variants cannot have defaults; write 'Name' or 'Name(field: Type)' and supply payload values when constructing a variant");
                }
                let id = self.id();
                cases.push(Case {
                    id,
                    pos: name.pos,
                    name: self.sym(name),
                    fields: payload,
                });
                self.end()?;
            } else if self.kind() == Tok::Fn
                || (self.kind() == Tok::Var && self.ahead(1).kind == Tok::Fn)
            {
                let mutating = self.take(Tok::Var);
                self.need(Tok::Fn)?;
                if token.kind == Tok::Type {
                    let t = self.previous();
                    let names = type_param_names(self.names, &type_params);
                    return self.fail(t, format!("a type declares only fields; write its methods after it as 'fn {name_t}{names}.name(...)'", name_t = self.names.str(name)));
                }
                let mname = self.need(Tok::Name)?;
                let m = self.method_signature(mname, true, false, mutating)?;
                self.end()?;
                methods.push(m);
            } else {
                let fname = self.need(Tok::Name)?;
                self.need_name_colon(fname)?;
                self.no_ref()?;
                let ty = self.typ()?;
                let default = if self.take(Tok::Assign) {
                    Some(self.expression(0)?)
                } else {
                    self.implicit_none(&ty)
                };
                let id = self.id();
                fields.push(Param {
                    id,
                    pos: fname.pos,
                    name: self.sym(fname),
                    ty: Some(ty),
                    default,
                    mutable: false,
                });
                self.end()?;
            }
        }
        self.need(Tok::Dedent)?;
        if token.kind == Tok::Interface && methods.is_empty() {
            return self.fail(token, "declaration body cannot be empty; an interface needs at least one 'fn name(...) Type' operation");
        }
        if token.kind == Tok::Enum && cases.is_empty() {
            return self.fail(
                token,
                "an enum must declare at least one variant; add 'Name' or 'Name(field: Type)'",
            );
        }
        let kind = match token.kind {
            Tok::Interface => DeclKind::Interface(InterfaceDecl {
                name,
                type_params,
                methods,
            }),
            Tok::Enum => DeclKind::Alternative(AlternativeDecl {
                name,
                type_params,
                cases,
                opaque: false,
            }),
            _ => DeclKind::Type(TypeDecl {
                name,
                type_params,
                fields,
                external: false,
                opaque: false,
            }),
        };
        let id = self.id();
        Ok(Decl {
            id,
            pos: token.pos,
            export: false,
            synthetic: false,
            kind,
        })
    }

    // ---- statements ----

    fn suite(&mut self) -> PResult<Vec<Stmt>> {
        self.statement_suite(false, false)
    }

    /// Parses `: body`. `expression` marks a lambda body (an inline body is its
    /// value); `fn_body` marks a function or method body (inline returns, may be empty).
    fn statement_suite(&mut self, expression: bool, fn_body: bool) -> PResult<Vec<Stmt>> {
        self.enter()?;
        let (outer, outer_return, outer_lambda) =
            (self.inline_statement, self.inline_return, self.block_lambda);
        let r = self.statement_suite_inner(expression, fn_body, outer, outer_lambda);
        self.inline_statement = outer;
        self.inline_return = outer_return;
        self.block_lambda = outer_lambda;
        self.depth -= 1;
        r
    }

    fn statement_suite_inner(
        &mut self,
        expression: bool,
        fn_body: bool,
        outer: bool,
        outer_lambda: bool,
    ) -> PResult<Vec<Stmt>> {
        self.need(Tok::Colon)?;
        if self.kind() == Tok::Ellipsis && fn_body {
            self.at += 1;
            self.end()?;
            return Ok(Vec::new());
        }
        if self.kind() != Tok::Newline {
            if self.kind() == Tok::If && (expression || fn_body) {
                // `fn x: if c: a else: b`: the body is the conditional expression.
                let (start, at) = (self.at, self.peek().pos);
                if let Ok(value) = self.expression(0)
                    && (expression || self.end().is_ok())
                {
                    let id = self.id();
                    return Ok(vec![Stmt {
                        id,
                        pos: at,
                        kind: StmtKind::Return(Some(value)),
                    }]);
                }
                // Not a conditional expression: report it as the statement it was written as.
                self.at = start;
            }
            if matches!(self.kind(), Tok::If | Tok::While | Tok::For) {
                let t = self.peek();
                return self.fail(t, format!("inline bodies require one simple statement; put '{}' on its own line in an indented block", t.kind.as_str()));
            }
            self.inline_statement = true;
            self.inline_return = expression || fn_body;
            let body = vec![self.statement(false)?];
            self.inline_statement = outer;
            if !expression {
                self.end()?;
            }
            return Ok(body);
        }
        self.inline_statement = false;
        self.inline_return = false;
        self.block_lambda = outer_lambda || expression;
        self.need(Tok::Newline)?;
        self.need(Tok::Indent)?;
        let mut body = Vec::new();
        loop {
            self.newlines();
            if self.kind() == Tok::Dedent || self.kind() == Tok::Eof {
                break;
            }
            self.statements(false, &mut body)?;
        }
        self.need(Tok::Dedent)?;
        if body.is_empty() {
            let t = self.previous();
            return self.fail(t, "suite cannot be empty; add at least one statement, or write '...' after the colon for a runtime-bound declaration");
        }
        Ok(body)
    }

    /// Rejects `ref`, which the language no longer has: a function that returns part of a
    /// parameter returns a borrow of it, a field owns its value, and a binding of a place already borrows it.
    fn no_ref(&mut self) -> PResult<()> {
        if self.kind() == Tok::Ref {
            let at = self.peek();
            return self.fail_fix(
                at,
                "`ref` was removed: drop it; a function that returns part of a parameter returns a borrow of it, with no marker, and a field owns its value",
                "",
            );
        }
        Ok(())
    }

    /// `let pattern = hidden`: the first statement of a `for` body or lambda whose
    /// parameter is a pattern. Checking, ownership, and lowering see an ordinary
    /// binding of the hidden name, which borrows the element.
    fn destructure(&mut self, pattern: Pattern, hidden: Symbol) -> Stmt {
        let pos = pattern.pos;
        let value = self.mk(pos, ExprKind::Name(hidden));
        let id = self.id();
        Stmt {
            id,
            pos,
            kind: StmtKind::Bind {
                mutable: false,
                pattern,
                ty: None,
                value,
                group: None,
            },
        }
    }

    /// Consumes the `:=` of an immutable binding. A leftover `=` after a
    /// type annotation gets a fix-it, since `=` binds only after `var`.
    fn need_immutable_bind(&mut self) -> PResult<()> {
        if self.kind() == Tok::Assign {
            let t = self.peek();
            return self.fail_fix(t, "an immutable binding uses ':=' after its type: write 'x: Type := value'; '=' binds only after 'var'", ":=");
        }
        self.need(Tok::ColonAssign).map(|_| ())
    }

    /// Whether the statement at the cursor starts an immutable binding:
    /// `name := v`, `name: Type := v`, or `[a, b] := v` / `{a, b} := v`.
    fn binding_ahead(&self) -> bool {
        match self.kind() {
            Tok::Name | Tok::Underscore => {
                matches!(self.ahead(1).kind, Tok::ColonAssign | Tok::Colon)
            }
            Tok::LBracket | Tok::LBrace => {
                let mut depth = 0usize;
                for i in self.at..self.tokens.len() {
                    match self.tokens[i].kind {
                        Tok::LParen | Tok::LBracket | Tok::LBrace => depth += 1,
                        Tok::RParen | Tok::RBracket | Tok::RBrace => {
                            depth -= 1;
                            if depth == 0 {
                                return self
                                    .tokens
                                    .get(i + 1)
                                    .is_some_and(|t| t.kind == Tok::ColonAssign);
                            }
                        }
                        Tok::Newline | Tok::Eof => return false,
                        _ => {}
                    }
                }
                false
            }
            _ => false,
        }
    }

    /// Parses a binding: `var pattern [: Type] = value` after `var`, or an
    /// immutable `name := value`, `name: Type := value`, or `pattern := value`.
    fn binding(&mut self, mutable: bool, group: Option<Pos>, pos: Pos) -> PResult<Stmt> {
        self.no_ref()?;
        let pattern = self.pattern()?;
        let mut ty = None;
        let named = matches!(pattern.kind, PatternKind::Name(_));
        if mutable {
            if named && self.take(Tok::Colon) {
                ty = Some(self.typ()?);
            }
            if self.kind() == Tok::ColonAssign {
                let t = self.peek();
                return self.fail_fix(t, "'var' binds with '=': write 'var x = value'; ':=' declares an immutable binding", "=");
            }
            self.need(Tok::Assign)?;
        } else {
            if named && self.take(Tok::Colon) {
                ty = Some(self.typ()?);
            }
            self.need_immutable_bind()?;
        }
        let value = self.expression(0)?;
        let id = self.id();
        Ok(Stmt {
            id,
            pos,
            kind: StmtKind::Bind {
                mutable,
                pattern,
                ty,
                value,
                group,
            },
        })
    }

    /// Parses one statement, plus the rest of its bindings for a group.
    fn statements(&mut self, allow_value: bool, out: &mut Vec<Stmt>) -> PResult<()> {
        let s = self.statement(allow_value)?;
        out.push(s);
        out.append(&mut self.queued);
        Ok(())
    }

    fn statement(&mut self, allow_value: bool) -> PResult<Stmt> {
        let t = self.peek();
        let pos = t.pos;
        let kind = match t.kind {
            Tok::Name | Tok::Underscore | Tok::LBracket | Tok::LBrace if self.binding_ahead() => {
                let s = self.binding(false, None, pos)?;
                self.end()?;
                return Ok(s);
            }
            Tok::Name
                if self.text(t) == "let"
                    && matches!(
                        self.ahead(1).kind,
                        Tok::Name | Tok::Underscore | Tok::LBracket | Tok::LBrace
                    ) =>
            {
                return self.fail(t, "'let' was removed; bind with 'x := value' (or 'x: Type := value'), destructure with '[a, b] := value', and use 'var x = value' for a mutable binding");
            }
            Tok::Var => {
                self.at += 1;
                let mutable = true;
                if self.kind() == Tok::LParen {
                    let mut entries: Vec<Stmt> = Vec::new();
                    self.binding_group(t, &mut |p: &mut Parser<'a>| {
                        let epos = p.peek().pos;
                        let e = p.binding(mutable, Some(t.pos), epos)?;
                        entries.push(e);
                        Ok(())
                    })?;
                    let mut it = entries.into_iter();
                    let first = it.next().expect("binding groups are nonempty");
                    self.queued = it.collect();
                    return Ok(first);
                }
                let s = self.binding(mutable, None, pos)?;
                self.end()?;
                return Ok(s);
            }
            Tok::Fn
                if self.ahead(1).kind == Tok::Name
                    && matches!(self.ahead(2).kind, Tok::LParen | Tok::LBracket) =>
            {
                self.at += 1;
                let name = self.need(Tok::Name)?;
                if self.kind() == Tok::LBracket {
                    let b = self.peek();
                    return self.fail(b, "a local fn cannot take type parameters; declare a generic function at module level");
                }
                let params = self.parameters(true, false)?;
                let result = Box::new(self.result_type()?);
                let body = self.statement_suite(true, false)?;
                let pid = self.id();
                let value = self.mk(
                    t.pos,
                    ExprKind::Lambda(Lambda {
                        params,
                        result: Some(result),
                        body,
                    }),
                );
                StmtKind::Bind {
                    mutable: false,
                    pattern: Pattern {
                        id: pid,
                        pos: name.pos,
                        kind: PatternKind::Name(self.sym(name)),
                    },
                    ty: None,
                    value,
                    group: None,
                }
            }
            Tok::Return => {
                self.at += 1;
                let mut value = None;
                let k = self.kind();
                if k != Tok::Newline
                    && !(self.inline_statement
                        && matches!(k, Tok::Comma | Tok::RParen | Tok::RBracket | Tok::RBrace))
                {
                    value = Some(self.expression(0)?);
                }
                self.end()?;
                StmtKind::Return(value)
            }
            Tok::Break | Tok::Continue => {
                self.at += 1;
                self.end()?;
                if t.kind == Tok::Break {
                    StmtKind::Break
                } else {
                    StmtKind::Continue
                }
            }
            Tok::If => {
                self.at += 1;
                let mut binding = None;
                let mut mutable = false;
                if self.kind() == Tok::Name
                    && self.text(self.peek()) == "let"
                    && self.ahead(1).kind == Tok::Name
                {
                    let l = self.peek();
                    return self.fail(l, "'if let' was removed; write 'if value := optional:' (or 'if var value = optional:' for a mutable binding)");
                }
                if self.kind() == Tok::Var
                    || (matches!(self.kind(), Tok::Name | Tok::Underscore)
                        && self.ahead(1).kind == Tok::ColonAssign)
                {
                    mutable = self.kind() == Tok::Var;
                    if mutable {
                        self.at += 1;
                    }
                    let pat = self.pattern()?;
                    if !matches!(pat.kind, PatternKind::Name(_)) {
                        return self.fail(t, "an if binding takes one name; write 'if value := optional:' and destructure the value inside the branch");
                    }
                    if self.kind() == Tok::LParen {
                        return self.fail(t, "an if binding unwraps an Optional or Result into one name; it does not match alternative cases. Write 'match value:' with a 'Case(x):' arm, or 'if value := optional:'");
                    }
                    binding = Some(pat);
                    self.need(if mutable {
                        Tok::Assign
                    } else {
                        Tok::ColonAssign
                    })?;
                }
                let cond = self.expression(0)?;
                let body = self.suite()?;
                self.newlines();
                let mut else_body = Vec::new();
                if self.take(Tok::Else) {
                    if self.kind() == Tok::If {
                        else_body = vec![self.statement(false)?];
                    } else {
                        else_body = self.suite()?;
                    }
                }
                StmtKind::If {
                    binding,
                    mutable,
                    cond,
                    body,
                    else_body,
                }
            }
            Tok::While => {
                self.at += 1;
                let cond = self.expression(0)?;
                let body = self.suite()?;
                StmtKind::While { cond, body }
            }
            Tok::For => {
                self.at += 1;
                if self.kind() == Tok::LParen {
                    let c = self.peek();
                    return self.fail(c, "for does not take parentheses or a counter clause; write 'for item in items:' to visit a List, or 'for i in 0..n:' to count");
                }
                self.no_ref()?;
                let (name, pattern) = if matches!(self.kind(), Tok::LBracket | Tok::LBrace) {
                    (self.names.intern(HIDDEN_ITEM), Some(self.pattern()?))
                } else {
                    let name = self.need(Tok::Name)?;
                    (self.sym(name), None)
                };
                if self.kind() == Tok::Name && self.text(self.peek()) == "of" {
                    let c = self.peek();
                    return self.fail(c, "for uses 'in', not 'of'; write 'for item in items:'");
                }
                if self.kind() == Tok::Comma {
                    let c = self.peek();
                    return self.fail(c, "for binds one name or one pattern; to read positions, loop over the entries, e.g. 'for entry in items.entries():' and use entry.index and entry.value (a Map's entries() give entry.key and entry.value), or destructure each element with 'for [a, b] in pairs:'");
                }
                self.need(Tok::In)?;
                let iter = self.expression(0)?;
                let mut body = self.suite()?;
                if let Some(pattern) = pattern {
                    body.insert(0, self.destructure(pattern, name));
                }
                StmtKind::For { name, iter, body }
            }
            _ => self.expression_statement(t, allow_value)?,
        };
        let id = self.id();
        Ok(Stmt { id, pos, kind })
    }

    fn expression_statement(&mut self, t: Token, allow_value: bool) -> PResult<StmtKind> {
        let e = self.expression(0)?;
        let kind = if self.compound_assignment() {
            self.compound(t, e)?
        } else if self.take(Tok::Assign) {
            if index_parts(&e).is_some() {
                let value = self.expression(0)?;
                let kind = self.index_set(e, value, false);
                self.end()?;
                return Ok(kind);
            }
            let target = self.assign_target(t, e)?;
            let value = self.expression(0)?;
            StmtKind::Assign {
                target,
                compound: None,
                value,
            }
        } else {
            let try_call = matches!(&e.kind, ExprKind::Unary { op: UnaryOp::Try, operand } if matches!(operand.kind, ExprKind::Call { .. }));
            let is_call = matches!(
                e.kind,
                ExprKind::Call { .. } | ExprKind::Match { .. } | ExprKind::Unit
            );
            if !self.inline_return && !is_call && !try_call && !allow_value {
                if let ExprKind::Name(n) = &e.kind {
                    match self.names.str(*n) {
                        "pass" => return self.fail(t, "'pass' is not a keyword; write 'unit' for an empty block or match arm"),
                        "const" | "val" | "final" => {
                            return self.fail(t, format!("'{n_t}' is not a keyword; write 'name := ...' for a binding that is not reassigned, or 'var name = ...' when it changes", n_t = self.names.str(n)));
                        }
                        "throw" | "raise" | "catch" => {
                            return self.fail(t, format!("'{n_t}' is not a keyword; failures are values; return error(...) from a fn returning T!, propagate a Result with 'call()?', or handle it with 'if value := result:' and an else branch", n_t = self.names.str(n)));
                        }
                        "elseif" => return self.fail(t, "'elseif' is not a keyword; write 'else if <condition>:' for a further branch"),
                        "elif" => return self.fail(t, "there is no 'elif': write 'else if <condition>:' for a further branch"),
                        "def" => return self.fail(t, "there is no 'def': declare a function with 'fn name(a: Int) Int:'"),
                        "switch" => return self.fail(t, "'switch' is not a keyword; write 'match value:' with one arm per case of your own type, or 'if x == a:' with 'else if' for plain values"),
                        "except" | "finally" => return self.fail(t, format!("'{n_t}' is not a keyword; failures are values; return error(...) from a fn returning T!, propagate a Result with 'call()?', or handle it with 'if value := result:' and an else branch", n_t = self.names.str(n))),
                        "loop" => return self.fail(t, "'loop' is not a keyword; write 'while true:' and leave it with 'break'"),
                        "foreach" => return self.fail(t, "'foreach' is not a keyword; write 'for item in items:'"),
                        "class" => return self.fail(t, "'class' is not a keyword inside a fn; declare a type with 'type Name:' at module level"),
                        "del" => return self.fail(t, "'del' is not a keyword; remove from a collection with its methods, such as xs.remove(i) or m.remove(key)"),
                        "global" | "nonlocal" => return self.fail(t, format!("'{n_t}' is not a keyword; a fn sees module constants directly, and mutable state lives in a 'var' or a field passed explicitly", n_t = self.names.str(n))),
                        "yield" => return self.fail(t, "'yield' is not a keyword; there are no generators, so build a list and return it"),
                        "async" | "await" => return self.fail(t, format!("'{n_t}' is not a keyword; call the function directly, or start concurrent work with promise(fn: ...) from \"@std/concurrency/promise.ms\"", n_t = self.names.str(n))),
                        "go" => return self.fail(t, "'go' is not a keyword; start concurrent work with promise(fn: ...) from \"@std/concurrency/promise.ms\": result := promise(fn: work()), then result.wait()"),
                        _ => {}
                    }
                }
                return self.fail(t, "only a call, a call followed by '?', or match can be a standalone expression statement; use 'name := ...' to keep the value, 'return' to return it, or call a function");
            }
            if self.inline_return {
                StmtKind::Return(Some(e))
            } else {
                StmtKind::Call(e)
            }
        };
        self.end()?;
        Ok(kind)
    }

    /// `xs[i] = value` as the call of the member `[]=`, which the checker resolves to `set` on a
    /// List and `add` on a Map.
    /// With `reread`, the value reads the same element, so a name or field key is cloned for the store
    /// and the original stays borrowable for the read (and for the caller afterwards).
    fn index_set(&mut self, target: Expr, value: Expr, reread: bool) -> StmtKind {
        let (left, index) = match target.kind {
            ExprKind::Index { left, index } => (left, index),
            ExprKind::Apply {
                left,
                value: Some(index),
                ..
            } => (left, index),
            _ => unreachable!("index target"),
        };
        let pos = target.pos;
        let index = if reread && matches!(index.kind, ExprKind::Name(_) | ExprKind::Member { .. }) {
            let receiver = Box::new(self.clone_chain(&index));
            let name = self.names.intern("clone");
            let callee = self.mk(
                index.pos,
                ExprKind::Member {
                    left: receiver,
                    name,
                },
            );
            Box::new(Expr {
                id: self.id(),
                pos: index.pos,
                end: index.end,
                kind: ExprKind::Call {
                    callee: Box::new(callee),
                    args: Vec::new(),
                },
            })
        } else {
            index
        };
        let member = self.mk(
            pos,
            ExprKind::Member {
                left,
                name: self.names.intern(INDEX_SET),
            },
        );
        let args = vec![
            Argument {
                pos: index.pos,
                name: None,
                value: *index,
                mutable: false,
            },
            Argument {
                pos: value.pos,
                name: None,
                value,
                mutable: false,
            },
        ];
        let call = self.mk(
            pos,
            ExprKind::Call {
                callee: Box::new(member),
                args,
            },
        );
        StmtKind::Call(call)
    }

    fn assign_target(&mut self, start: Token, e: Expr) -> PResult<AssignTarget> {
        match e.kind {
            ExprKind::Name(n) if self.names.str(n) != "self" && self.names.str(n) != "fixture" => Ok(AssignTarget::Name(n)),
            ExprKind::Member { .. } => Ok(AssignTarget::Member(e)),
            _ => self.fail(start, "assignment requires a local binding name or type field; the left side of '=' must be a name or a.field; to change a collection element, write xs[index] = value on a List or m[key] = value on a Map"),
        }
    }

    /// Parses `target op= value` as the assignment `target = target op value`.
    fn compound(&mut self, start: Token, e: Expr) -> PResult<StmtKind> {
        let op = self.peek();
        let equal = self.ahead(1);
        let plain = plain_chain(&e);
        let copy = if plain {
            Some(self.clone_chain(&e))
        } else {
            None
        };
        if let Some(copy) = &copy
            && index_parts(&e).is_some()
        {
            self.at += 2;
            let bop = arith_op(op.kind).expect("compound operator");
            let right = self.expression(0)?;
            let id = self.id();
            let value = Expr {
                id,
                pos: op.pos,
                end: right.end,
                kind: ExprKind::Binary {
                    op: bop,
                    left: Box::new(copy.clone()),
                    right: Box::new(right),
                },
            };
            return Ok(self.index_set(e, value, true));
        }
        let target = self.assign_target(start, e)?;
        let Some(left) = copy else {
            let text = op.kind.as_str();
            let mut d = Diagnostic::parse(
                self.file,
                op.pos,
                format!(
                    "compound assignment '{text}=' needs a name or a.field target whose receiver is names only; bind the receiver to a name first, or write the assignment out"
                ),
            );
            d.end = Some(equal.end);
            d.phase = Phase::Parse;
            return Err(Box::new(d));
        };
        self.at += 2;
        let bop = arith_op(op.kind).expect("compound operator");
        let right = self.expression(0)?;
        let id = self.id();
        let value = Expr {
            id,
            pos: op.pos,
            end: right.end,
            kind: ExprKind::Binary {
                op: bop,
                left: Box::new(left),
                right: Box::new(right),
            },
        };
        Ok(StmtKind::Assign {
            target,
            compound: Some(bop),
            value,
        })
    }

    fn clone_chain(&mut self, e: &Expr) -> Expr {
        let id = self.id();
        let kind = match &e.kind {
            ExprKind::Member { left, name } => ExprKind::Member {
                left: Box::new(self.clone_chain(left)),
                name: *name,
            },
            ExprKind::Index { left, index } => ExprKind::Index {
                left: Box::new(self.clone_chain(left)),
                index: Box::new(self.clone_chain(index)),
            },
            ExprKind::Apply { left, types, value } => ExprKind::Apply {
                left: Box::new(self.clone_chain(left)),
                types: self.copy_types(types),
                value: value.as_ref().map(|v| Box::new(self.clone_chain(v))),
            },
            other => other.clone(),
        };
        Expr {
            id,
            pos: e.pos,
            end: e.end,
            kind,
        }
    }

    fn compound_assignment(&self) -> bool {
        if arith_op(self.kind()).is_some() && self.at + 1 < self.tokens.len() {
            let next = self.tokens[self.at + 1];
            return next.kind == Tok::Assign && self.peek().end.offset == next.pos.offset;
        }
        false
    }

    // ---- patterns ----

    fn pattern(&mut self) -> PResult<Pattern> {
        self.enter()?;
        let r = self.pattern_inner();
        self.depth -= 1;
        r
    }

    fn pattern_inner(&mut self) -> PResult<Pattern> {
        let t = self.peek();
        if t.kind == Tok::Unit {
            return self.fail(t, "unit is a reserved value keyword, not a binding name; choose another name such as code_unit, and use unit for the Unit value");
        }
        if self.take(Tok::Name) {
            let id = self.id();
            return Ok(Pattern {
                id,
                pos: t.pos,
                kind: PatternKind::Name(self.sym(t)),
            });
        }
        // `_` binds a value nothing reads, such as a `Result` ignored on purpose.
        if self.take(Tok::Underscore) {
            let id = self.id();
            return Ok(Pattern {
                id,
                pos: t.pos,
                kind: PatternKind::Name(self.names.intern("_")),
            });
        }
        if self.take(Tok::LBracket) {
            let mut elements = Vec::new();
            if !self.take(Tok::RBracket) {
                loop {
                    elements.push(self.pattern()?);
                    if !self.take(Tok::Comma) {
                        break;
                    }
                    if self.kind() == Tok::RBracket {
                        break;
                    }
                }
                self.need(Tok::RBracket)?;
            }
            let id = self.id();
            return Ok(Pattern {
                id,
                pos: t.pos,
                kind: PatternKind::List(elements),
            });
        }
        if self.take(Tok::LBrace) {
            let mut fields = Vec::new();
            loop {
                let name = self.need(Tok::Name)?;
                let child = if self.take(Tok::Colon) {
                    self.pattern()?
                } else {
                    let id = self.id();
                    Pattern {
                        id,
                        pos: name.pos,
                        kind: PatternKind::Name(self.sym(name)),
                    }
                };
                fields.push(PatternField {
                    pos: name.pos,
                    name: self.sym(name),
                    pattern: child,
                });
                if !self.take(Tok::Comma) {
                    break;
                }
                if self.kind() == Tok::RBrace {
                    break;
                }
            }
            self.need(Tok::RBrace)?;
            let id = self.id();
            return Ok(Pattern {
                id,
                pos: t.pos,
                kind: PatternKind::Type(fields),
            });
        }
        let msg = format!(
            "expected a binding name, list pattern, or type pattern, found {}; write a name, [a, b], or {{x, y}}",
            describe(self.src, t)
        );
        self.fail(t, msg)
    }

    // ---- expressions ----

    fn mk(&mut self, pos: Pos, kind: ExprKind) -> Expr {
        let id = self.id();
        let end = if self.at > 0 {
            self.previous().end
        } else {
            pos
        };
        Expr { id, pos, end, kind }
    }

    fn expression(&mut self, min: u8) -> PResult<Expr> {
        self.enter()?;
        let r = self.expression_inner(min);
        self.depth -= 1;
        r
    }

    fn expression_inner(&mut self, min: u8) -> PResult<Expr> {
        let t = self.peek();
        if t.kind == Tok::Not && min > 3 {
            return self.fail(t, "not requires grouping at this operator position; wrap it in parentheses, e.g. a == (not b)");
        }
        let mut e;
        if self.take(Tok::Not) {
            let operand = self.expression(3)?;
            e = self.mk(
                t.pos,
                ExprKind::Unary {
                    op: UnaryOp::Not,
                    operand: Box::new(operand),
                },
            );
        } else if t.kind == Tok::Try {
            return self.fail(t, TRY_REMOVED);
        } else if matches!(t.kind, Tok::Plus | Tok::Minus) {
            self.at += 1;
            let op = match t.kind {
                Tok::Plus => UnaryOp::Plus,
                _ => UnaryOp::Neg,
            };
            let operand = self.expression(8)?;
            e = self.mk(
                t.pos,
                ExprKind::Unary {
                    op,
                    operand: Box::new(operand),
                },
            );
        } else {
            e = self.primary()?;
        }
        let mut compared = false;
        let mut links = 0usize;
        loop {
            let op = self.peek();
            if self.compound_assignment() {
                break;
            }
            if op.kind == Tok::Amp {
                return self.and_and(op);
            }
            if op.kind == Tok::Pipe {
                if min > 0 {
                    break;
                }
                self.link(&mut links)?;
                e = self.pipe(e)?;
                if self.kind() == Tok::Dot {
                    e = self.postfix(e)?;
                }
                if binary_op(self.kind()).is_some() {
                    let t = self.peek();
                    return self.fail(t, "a pipe has the lowest precedence; parenthesize it to use its result in an operator, e.g. (x | f) == y");
                }
                continue;
            }
            if op.kind == Tok::DotDot {
                if min > RANGE_LEVEL {
                    break;
                }
                self.at += 1;
                let right = self.expression(RANGE_LEVEL + 1)?;
                if self.kind() == Tok::DotDot {
                    let t = self.peek();
                    return self.fail(t, "a range cannot chain; write one 'start..end', or use range_by for a step from \"@std/collections/collections.ms\"");
                }
                e = self.range(e, right);
                continue;
            }
            let Some(bop) = binary_op(op.kind) else { break };
            let level = bop.precedence();
            if level < min {
                break;
            }
            if (op.kind == Tok::Plus || op.kind == Tok::Minus)
                && matches!(e.kind, ExprKind::Name(_))
                && self.ahead(1).kind == op.kind
                && self.ahead(2).kind == Tok::Newline
            {
                let n = match &e.kind {
                    ExprKind::Name(n) => *n,
                    _ => unreachable!(),
                };
                let o = op.kind.as_str();
                return self.fail(
                    op,
                    format!(
                        "Manuscript has no '{o}{o}' operator; write '{n_t} {o}= 1'",
                        n_t = self.names.str(n)
                    ),
                );
            }
            if level == 4 && compared {
                return self.fail(op, "comparison operators cannot chain; combine two comparisons with 'and', e.g. a < b and b < c");
            }
            self.at += 1;
            self.link(&mut links)?;
            let right = self.expression(level + 1)?;
            e = self.mk(
                op.pos,
                ExprKind::Binary {
                    op: bop,
                    left: Box::new(e),
                    right: Box::new(right),
                },
            );
            if level == 4 {
                compared = true;
            }
        }
        Ok(e)
    }

    /// `start..end` as the call `range(start, end)`; `..` names the standard `range`.
    fn range(&mut self, start: Expr, end: Expr) -> Expr {
        let pos = start.pos;
        let callee = self.mk(pos, ExprKind::Name(self.names.intern("..")));
        let args = [start, end]
            .into_iter()
            .map(|value| Argument {
                pos: value.pos,
                name: None,
                value,
                mutable: false,
            })
            .collect();
        self.mk(
            pos,
            ExprKind::Call {
                callee: Box::new(callee),
                args,
            },
        )
    }

    /// `&&` (two `&` tokens) where `and` was meant.
    fn and_and<T>(&self, first: Token) -> PResult<T> {
        let last = if self.ahead(1).kind == Tok::Amp && self.ahead(1).pos.offset == first.end.offset
        {
            self.ahead(1)
        } else {
            first
        };
        self.fail_word_operator(
            first,
            last,
            "'&&' is not an operator; write 'and' for logical and",
            "and",
        )
    }

    /// Parses one `| step` after `lhs` and desugars it to the ordinary
    /// expression the step names (see the module docs of [`crate::ast`]).
    fn pipe(&mut self, lhs: Expr) -> PResult<Expr> {
        self.at += 1;
        if self.kind() == Tok::Pipe {
            let t = self.peek();
            let first = self.previous();
            return self.fail_word_operator(first, t, "'||' is not an operator; write 'or' for logical or, and '|' only to start a pipe step", "or");
        }
        if self.kind() == Tok::Try {
            let t = self.peek();
            return self.fail(t, TRY_REMOVED);
        }
        let mut step;
        if self.kind() == Tok::Dot {
            step = self.postfix(lhs)?;
        } else {
            let name = self.peek();
            if name.kind != Tok::Name {
                let mut hint = "";
                if name.kind == Tok::Newline {
                    hint = "; to continue a flow on the next line, end this line before '|' and start the next line with '|'";
                }
                let msg = format!(
                    "a pipe step is a function name, a call without its first argument, or a '.method' step; write x | f, x | f(a: 1), or x | .method(a: 1), found {}{}",
                    describe(self.src, name),
                    hint
                );
                return self.fail(name, msg);
            }
            self.at += 1;
            let mut callee = self.mk(name.pos, ExprKind::Name(self.sym(name)));
            let mut links = 0;
            // A '.' on a later line continues the flow and applies to the step's
            // result, so it never extends the step's name path.
            while self.kind() == Tok::Dot
                && self.peek().pos.line == self.tokens[self.at - 1].pos.line
            {
                self.link(&mut links)?;
                self.at += 1;
                let member = self.need(Tok::Name)?;
                callee = self.mk(
                    member.pos,
                    ExprKind::Member {
                        left: Box::new(callee),
                        name: self.sym(member),
                    },
                );
            }
            if self.kind() == Tok::LBracket {
                let t = self.peek();
                return self.fail(t, format!("a pipe step cannot take type arguments; bind the instance to a name first, e.g. step := {}[Int], then write x | step", self.text(name)));
            }
            let mut args = vec![Argument {
                pos: lhs.pos,
                name: None,
                value: lhs,
                mutable: false,
            }];
            if self.take(Tok::LParen) {
                args.extend(self.call_arguments()?);
            }
            step = self.mk(
                name.pos,
                ExprKind::Call {
                    callee: Box::new(callee),
                    args,
                },
            );
        }
        if self.kind() == Tok::Question {
            let question = self.peek();
            self.at += 1;
            step = self.mk(
                question.pos,
                ExprKind::Unary {
                    op: UnaryOp::Try,
                    operand: Box::new(step),
                },
            );
        }
        Ok(step)
    }

    fn case_path(&mut self) -> PResult<Expr> {
        let t = self.need(Tok::Name)?;
        let mut e = self.mk(t.pos, ExprKind::Name(self.sym(t)));
        if self.take(Tok::LBracket) {
            let types = self.type_args()?;
            e = self.mk(
                t.pos,
                ExprKind::Apply {
                    left: Box::new(e),
                    types,
                    value: None,
                },
            );
        }
        let mut links = 0;
        while self.take(Tok::Dot) {
            self.link(&mut links)?;
            let name = self.need(Tok::Name)?;
            e = self.mk(
                name.pos,
                ExprKind::Member {
                    left: Box::new(e),
                    name: self.sym(name),
                },
            );
        }
        Ok(e)
    }

    fn primary(&mut self) -> PResult<Expr> {
        let t = self.peek();
        self.at += 1;
        let e = match t.kind {
            Tok::Name | Tok::SelfKw | Tok::Fixture => self.mk(t.pos, ExprKind::Name(self.sym(t))),
            Tok::Number => self.mk(t.pos, ExprKind::Number(self.sym(t))),
            Tok::True => self.mk(t.pos, ExprKind::Bool(true)),
            Tok::False => self.mk(t.pos, ExprKind::Bool(false)),
            Tok::String => {
                let parts = self.text_parts_of(t)?;
                self.mk(t.pos, ExprKind::Text(parts))
            }
            Tok::Unit => self.mk(t.pos, ExprKind::Unit),
            Tok::LParen if self.kind() == Tok::RParen => {
                return self.fail(t, "'()' is not a value; the Unit value is written 'unit'");
            }
            Tok::LParen => {
                let e = self.expression(0)?;
                if self.kind() == Tok::Comma {
                    let c = self.peek();
                    return self.fail(c, "Manuscript has no tuples; declare a type with 'type Pair:' and named fields, or use a List when the items share one type");
                }
                self.need(Tok::RParen)?;
                e
            }
            Tok::LBracket => {
                let mut items = Vec::new();
                if !self.take(Tok::RBracket) {
                    loop {
                        items.push(self.expression(0)?);
                        if !self.take(Tok::Comma) {
                            break;
                        }
                        if self.kind() == Tok::RBracket {
                            break;
                        }
                    }
                    self.need(Tok::RBracket)?;
                }
                self.mk(t.pos, ExprKind::List(items))
            }
            Tok::Match => {
                self.no_ref()?;
                let scrutinee = self.expression(0)?;
                let arms = self.match_arms(t)?;
                self.mk(
                    t.pos,
                    ExprKind::Match {
                        scrutinee: Box::new(scrutinee),
                        arms,
                    },
                )
            }
            Tok::LBrace => {
                let mut entries = Vec::new();
                if !self.take(Tok::RBrace) {
                    loop {
                        let key = self.expression(0)?;
                        if matches!(self.kind(), Tok::Comma | Tok::RBrace) {
                            let at = self.peek();
                            return self.fail(
                                at,
                                "a brace literal is a Map and needs 'key: value' entries; there is no set literal, so write Set[T]() and call add(value), or [a, b].to_set() from a List",
                            );
                        }
                        self.need(Tok::Colon)?;
                        let value = self.expression(0)?;
                        entries.push(MapEntry { key, value });
                        if !self.take(Tok::Comma) || self.kind() == Tok::RBrace {
                            break;
                        }
                    }
                    self.need(Tok::RBrace)?;
                }
                self.mk(t.pos, ExprKind::Map(entries))
            }
            Tok::Fn => {
                let mut result = None;
                let mut destructured = Vec::new();
                let params = if self.kind() == Tok::LParen {
                    let params = self.parameters(true, true)?;
                    if self.kind() == Tok::Arrow {
                        let a = self.peek();
                        return self.fail_fix(a, "result types follow the parameter list without an arrow; remove '->', e.g. fn (x: Int) Int: x + 1", "");
                    }
                    if self.kind() != Tok::Colon {
                        result = Some(Box::new(self.typ()?));
                    }
                    params
                } else {
                    let mut params = Vec::new();
                    while matches!(self.kind(), Tok::Name | Tok::LBracket | Tok::LBrace)
                        || (self.kind() == Tok::Var && self.ahead(1).kind == Tok::Name)
                    {
                        if matches!(self.kind(), Tok::LBracket | Tok::LBrace) {
                            // `fn [a, b]: ...` binds the pattern from a hidden parameter.
                            let pattern = self.pattern()?;
                            let hidden = self
                                .names
                                .intern(&format!("{HIDDEN_ITEM} {}", params.len()));
                            let id = self.id();
                            params.push(Param {
                                id,
                                pos: pattern.pos,
                                name: hidden,
                                ty: None,
                                default: None,
                                mutable: false,
                            });
                            destructured.push(self.destructure(pattern, hidden));
                            if !self.take(Tok::Comma) {
                                break;
                            }
                            continue;
                        }
                        // `fn var exchange, next: ...`: a parameter the function changes in place.
                        let mutable = self.take(Tok::Var);
                        let name = self.next();
                        let id = self.id();
                        params.push(Param {
                            id,
                            pos: name.pos,
                            name: self.sym(name),
                            ty: None,
                            default: None,
                            mutable,
                        });
                        if !self.take(Tok::Comma) {
                            break;
                        }
                    }
                    params
                };
                let mut body = self.statement_suite(true, false)?;
                body.splice(0..0, destructured);
                self.mk(
                    t.pos,
                    ExprKind::Lambda(Lambda {
                        params,
                        result,
                        body,
                    }),
                )
            }
            Tok::If => self.if_expression(t)?,
            _ => {
                let before = if self.at > 1 {
                    self.tokens[self.at - 2].kind
                } else {
                    Tok::Eof
                };
                let hint = match (t.kind, before) {
                    (Tok::Else, _) => {
                        "'else' continues an 'if' block: put it on its own line at the same indentation as that 'if', directly after the if body"
                    }
                    (Tok::Gt, Tok::Lt) => "'<>' is not an operator; write '!=' for inequality",
                    (Tok::Star, Tok::Star) => {
                        "there is no '**' power operator; multiply explicitly or call a function from @std/math/math.ms"
                    }
                    (Tok::Comma | Tok::RParen, Tok::Colon) => {
                        "a label before ':' needs a value, e.g. count: 1"
                    }
                    (Tok::Comma, _) => "remove the extra comma or add the missing value before it",
                    _ => "write a value, name, call, or literal here",
                };
                let msg = format!(
                    "expected an expression, found {}; {hint}",
                    describe(self.src, t)
                );
                return self.fail(t, msg);
            }
        };
        self.postfix(e)
    }

    /// Applies member access, indexing and calls to `e`.
    fn postfix(&mut self, mut e: Expr) -> PResult<Expr> {
        let mut links = 0usize;
        // Receivers of `?.` links, outermost first: the rest of the chain
        // applies to the present payload, so each becomes a match at the end.
        let mut chains: Vec<(Expr, Symbol)> = Vec::new();
        loop {
            if self.kind() == Tok::Question
                && self.ahead(1).kind == Tok::Dot
                && self.ahead(1).pos.offset == self.peek().end.offset
                && self.at > 0
                && self.previous().end.offset == self.peek().pos.offset
            {
                self.at += 1;
                let question = self.previous();
                let binding = self.names.intern(&format!("?{}", chains.len()));
                let present = self.mk(question.pos, ExprKind::Name(binding));
                chains.push((std::mem::replace(&mut e, present), binding));
                // The `.` is read as an ordinary member link on the payload.
                continue;
            }
            if self.take(Tok::Dot) {
                self.link(&mut links)?;
                if self.kind() == Tok::Number {
                    let t = self.peek();
                    return self.fail(t, "a number has at most one decimal point and member access needs a name; write the number once, e.g. 1.2");
                }
                let name = self.need(Tok::Name)?;
                e = self.mk(
                    name.pos,
                    ExprKind::Member {
                        left: Box::new(e),
                        name: self.sym(name),
                    },
                );
            } else if self.take(Tok::LBracket) {
                self.link(&mut links)?;
                e = self.bracket(e)?;
            } else if self.take(Tok::LParen) {
                self.link(&mut links)?;
                let pos = e.pos;
                let args = self.call_arguments()?;
                e = self.mk(
                    pos,
                    ExprKind::Call {
                        callee: Box::new(e),
                        args,
                    },
                );
            } else if self.kind() == Tok::Question && index_parts(&e).is_some() {
                self.at += 1;
                let pos = e.pos;
                e = self.mk(pos, ExprKind::Probe(Box::new(e)));
            } else if self.kind() == Tok::Question {
                // `call()?` is `try call()`; one per value keeps a line readable.
                let question = self.peek();
                self.at += 1;
                if self.kind() == Tok::Dot && self.peek().pos.offset == question.end.offset {
                    return self.fail(question, "write '?.' with no space before it, as in a?.b; to propagate a Result error before a member, write '(call()?).member'");
                }
                if self.kind() == Tok::Question {
                    let second = self.peek();
                    return self.fail(second, "'??' is not an operator and '?' cannot repeat: unwrap an Optional with 'if x := v:' or give it a default with 'v.get(default)', or bind a Result to a name before the next '?'");
                }
                let pos = e.pos;
                e = self.mk(
                    pos,
                    ExprKind::Unary {
                        op: UnaryOp::Try,
                        operand: Box::new(e),
                    },
                );
            } else {
                break;
            }
        }
        while let Some((receiver, binding)) = chains.pop() {
            e = self.chain_match(receiver, binding, e);
        }
        Ok(e)
    }

    /// `receiver?.rest`, with `rest` already applied to `binding`: a match
    /// that yields `rest` when the receiver is present and `none` otherwise.
    fn chain_match(&mut self, receiver: Expr, binding: Symbol, rest: Expr) -> Expr {
        let pos = receiver.pos;
        let mut arms = Vec::new();
        for (case, bindings, value) in [
            ("some", vec![ArmBinding { name: binding, pos }], rest),
            (
                "none",
                Vec::new(),
                self.mk(pos, ExprKind::Name(self.names.intern("none"))),
            ),
        ] {
            let path = self.mk(pos, ExprKind::Name(self.names.intern(case)));
            let id = self.id();
            arms.push(Arm {
                id,
                pos,
                path,
                bindings,
                body: Vec::new(),
                value: Some(value),
                from_if: false,
                chain: true,
                bare: false,
            });
        }
        self.mk(
            pos,
            ExprKind::Match {
                scrutinee: Box::new(receiver),
                arms,
            },
        )
    }

    /// Parses the arguments after an opening parenthesis, through `)`.
    fn call_arguments(&mut self) -> PResult<Vec<Argument>> {
        let mut args = Vec::new();
        if !self.take(Tok::RParen) {
            loop {
                let pos = self.peek().pos;
                let mut name = None;
                if self.kind() == Tok::Name && self.ahead(1).kind == Tok::Colon {
                    name = Some(self.sym(self.peek()));
                    self.at += 2;
                }
                if self.kind() == Tok::Name && self.ahead(1).kind == Tok::Assign {
                    let eq = self.ahead(1);
                    let n = self.text(self.peek());
                    return self.fail(eq, format!("argument labels use a colon; write {n}: value"));
                }
                let mutable = self.take(Tok::Var);
                let value = self.expression(0)?;
                if let ExprKind::Name(n) = &value.kind
                    && self.kind() == Tok::Arrow
                {
                    let a = self.peek();
                    return self.fail(a, format!("arrow closures are not supported; write 'fn {n_t}: {n_t} + 1', or 'fn({n_t}: Int) Int: {n_t} + 1' with explicit types", n_t = self.names.str(n)));
                }
                args.push(Argument {
                    pos,
                    name,
                    value,
                    mutable,
                });
                if !self.take(Tok::Comma) {
                    break;
                }
                if self.kind() == Tok::RParen {
                    break;
                }
            }
            self.need(Tok::RParen)?;
        }
        Ok(args)
    }

    // ---- text ----

    /// Rejects multi-line text where only a one-line name or path fits.
    fn single_line(&self, token: Token, what: &str) -> PResult<()> {
        let full = self.text(token);
        if full.starts_with("\"\"\"") || full.starts_with("r\"\"\"") {
            return self.fail(
                token,
                format!("{what} are one-line text; write them with a single pair of quotes"),
            );
        }
        Ok(())
    }

    /// Decodes a text token into literal and interpolated parts.
    fn text_parts_of(&mut self, token: Token) -> PResult<Vec<TextPart>> {
        let full = self.text(token);
        if let Some(body) = full.strip_prefix("r\"\"\"") {
            let (content, indent, _) = multiline_body(&body[..body.len() - 3]);
            return Ok(vec![TextPart::Lit(dedent(content, indent).into())]);
        }
        if full.starts_with("\"\"\"") {
            return self.text_parts(token, &full[3..full.len() - 3], 3);
        }
        if let Some(body) = full.strip_prefix("r\"") {
            return Ok(vec![TextPart::Lit(body[..body.len() - 1].into())]);
        }
        let raw = &full[1..full.len() - 1];
        if !raw.bytes().any(|b| b == b'\\' || b == b'{') {
            return Ok(vec![TextPart::Lit(raw.into())]);
        }
        self.text_parts(token, raw, 1)
    }

    /// `quotes` is the width of the opening delimiter; `raw` excludes both
    /// delimiters. A multi-line body drops its first and last line break and
    /// the closing line's indentation from every line.
    fn text_parts(&mut self, token: Token, raw: &str, quotes: usize) -> PResult<Vec<TextPart>> {
        let rb = raw.as_bytes();
        let (first, end, indent) = if quotes == 3 {
            let (content, indent, first) = multiline_body(raw);
            (first, first + content.len(), indent)
        } else {
            (0, rb.len(), 0)
        };
        let mut parts: Vec<TextPart> = Vec::new();
        let mut literal: Vec<u8> = Vec::new();
        let flush = |literal: &mut Vec<u8>, parts: &mut Vec<TextPart>| {
            if !literal.is_empty() {
                let s = String::from_utf8(std::mem::take(literal)).expect("text is valid UTF-8");
                parts.push(TextPart::Lit(s.into_boxed_str()));
            }
        };
        let mut i = first;
        let mut line_start = indent > 0;
        let (mut positioned, mut position) = (0, token.pos);
        while i < end {
            if line_start {
                line_start = false;
                let mut skipped = 0;
                while skipped < indent && i < end && matches!(rb[i], b' ' | b'\t') {
                    skipped += 1;
                    i += 1;
                }
                continue;
            }
            let mut c = rb[i];
            i += 1;
            if c == b'\\' {
                c = rb[i];
                i += 1;
                match c {
                    b'n' => literal.push(b'\n'),
                    b'r' => literal.push(b'\r'),
                    b't' => literal.push(b'\t'),
                    b'u' => {
                        let start = i + 1;
                        i = start;
                        while rb[i] != b'}' {
                            i += 1;
                        }
                        let n = u32::from_str_radix(&raw[start..i], 16).unwrap_or(0xfffd);
                        let ch = char::from_u32(n).unwrap_or('\u{fffd}');
                        let mut buf = [0u8; 4];
                        literal.extend_from_slice(ch.encode_utf8(&mut buf).as_bytes());
                        i += 1;
                    }
                    other => literal.push(other),
                }
                continue;
            }
            if c != b'{' {
                literal.push(c);
                line_start = c == b'\n' && indent > 0;
                continue;
            }
            flush(&mut literal, &mut parts);
            let start = i;
            let brace = self.source_origin + token.lo as usize + quotes + start - 1;
            i = self
                .boundaries
                .interpolation_end(brace)
                .expect("validated interpolation")
                - (self.source_origin + token.lo as usize + quotes);
            let source = &raw[start..i - 1];
            // Advance through each prefix once, including physical lines in
            // multiline text. Interpolation expressions themselves have no newlines.
            let at = quotes + start;
            position = text_pos(
                position,
                &self.text(token)[positioned..],
                at - positioned,
                self.boundaries,
            );
            positioned = at;
            let value = self.interpolation(token, at, source, position)?;
            parts.push(TextPart::Interp(value));
        }
        flush(&mut literal, &mut parts);
        if parts.is_empty() {
            parts.push(TextPart::Lit("".into()));
        }
        Ok(parts)
    }

    /// Lexes and parses the expression inside one `{...}` of a text literal.
    /// Failures also state the escape for a literal brace.
    fn interpolation(
        &mut self,
        token: Token,
        at: usize,
        source: &str,
        position: Pos,
    ) -> PResult<Expr> {
        let suffix = format!(
            " ('{{' at column {} starts an interpolation; write \\{{ and \\}} for literal braces)",
            position.column - 1
        );
        let origin = self.source_origin + token.lo as usize + at;
        // The lexer rejects physical newlines inside an interpolation. Map
        // each token from its relative byte offset without rescanning the text.
        let shift = |p: Pos| -> Pos {
            let offset = p.offset.min(source.len() as u32);
            Pos::new(
                position.offset + offset,
                position.line,
                position.column + offset,
            )
        };
        let mut tokens =
            match crate::lexer::lex_interpolation(self.file, source, origin, self.boundaries) {
                Ok(tokens) => tokens,
                Err(_) => return self.interpolation_wrapped(token, at, source),
            };
        for t in &mut tokens {
            t.pos = shift(t.pos);
            t.end = shift(t.end);
        }
        let mut nested = Parser::new(
            self.file,
            source,
            tokens,
            self.boundaries,
            origin,
            self.depth,
            self.next_id,
        );
        let result: PResult<Expr> = (|| {
            let value = nested.expression(0)?;
            nested.newlines();
            if nested.kind() != Tok::Eof {
                let at = nested.peek();
                let found = describe(source, at);
                return nested.fail(
                    at,
                    format!("an interpolation holds one expression, found {found} after it; close the brace after the expression, or bind the rest to a name first"),
                );
            }
            Ok(value)
        })();
        self.next_id = nested.next_id;
        match result {
            Ok(v) => Ok(v),
            Err(mut d) => {
                d.message.push_str(&suffix);
                Err(d)
            }
        }
    }

    // ---- match ----

    /// `if c: a else: b` (also `else if`) as a match over the Bool `c`.
    fn if_expression(&mut self, t: Token) -> PResult<Expr> {
        let cond = self.expression(0)?;
        self.need(Tok::Colon)?;
        if self.kind() == Tok::Newline {
            let at = self.peek();
            return self.fail(at, "an if expression writes its branches on one line, 'if c: a else: b'; to run statements, use an if statement that assigns a 'var' or returns");
        }
        let then = self.expression(0)?;
        if self.kind() != Tok::Else {
            let at = self.peek();
            return self.fail(at, "an if expression needs an else branch; write 'if c: a else: b', or use an if statement when no value is needed");
        }
        let else_token = self.peek();
        self.at += 1;
        let els = if self.kind() == Tok::If {
            let nested = self.peek();
            self.at += 1;
            self.if_expression(nested)?
        } else {
            self.need(Tok::Colon)?;
            self.expression(0)?
        };
        let mut arms = Vec::new();
        for (value, branch, pos) in [(true, then, t.pos), (false, els, else_token.pos)] {
            let path = self.mk(pos, ExprKind::Bool(value));
            let id = self.id();
            arms.push(Arm {
                id,
                pos,
                path,
                bindings: Vec::new(),
                body: Vec::new(),
                value: Some(branch),
                from_if: true,
                chain: false,
                bare: false,
            });
        }
        Ok(self.mk(
            t.pos,
            ExprKind::Match {
                scrutinee: Box::new(cond),
                arms,
            },
        ))
    }

    fn match_arms(&mut self, header: Token) -> PResult<Vec<Arm>> {
        let mut arms: Vec<Arm> = Vec::new();
        self.need(Tok::Colon)?;
        self.need(Tok::Newline)?;
        self.need(Tok::Indent)?;
        loop {
            self.newlines();
            if self.kind() == Tok::Dedent {
                if arms.is_empty() {
                    return self.fail(header, "match requires at least one arm; add a case pattern or '_' arm under the header");
                }
                break;
            }
            if let Some(prefix) = self.legacy_case_prefix() {
                return self.fail_fix(prefix, "match arms use bare variant names, e.g. Paid(receipt): or Missing:; remove the legacy 'case' prefix", "");
            }
            let start = self.peek();
            let k = start.kind;
            let literal = matches!(k, Tok::Number | Tok::True | Tok::False | Tok::String)
                || (k == Tok::Minus && self.ahead(1).kind == Tok::Number);
            let mut bindings = Vec::new();
            let mut bare = false;
            let path;
            if literal {
                path = self.expression(0)?;
            } else if self.take(Tok::Underscore) {
                path = self.mk(start.pos, ExprKind::Name(self.names.intern("_")));
            } else {
                let written = self.case_path()?;
                if let ExprKind::Name(n) = &written.kind
                    && self.names.str(*n) == "some"
                    && self.kind() == Tok::LParen
                    && self.speculative == 0
                {
                    let t = self.peek();
                    return self.fail(t, "there is no some pattern; write the payload name alone, e.g. 'value:' beside 'none:'");
                }
                if let ExprKind::Name(n) = &written.kind
                    && self.kind() != Tok::LParen
                    && self.names.str(*n) != "none"
                    && self
                        .names
                        .str(*n)
                        .starts_with(|c: char| c.is_ascii_lowercase() || c == '_')
                {
                    // The checker distinguishes an Optional payload binding from
                    // a lowercase variant using the scrutinee's type.
                    bindings.push(ArmBinding {
                        name: *n,
                        pos: start.pos,
                    });
                    bare = true;
                }
                path = written;
                if self.take(Tok::LParen) {
                    loop {
                        let tok = self.peek();
                        if !self.take(Tok::Underscore) {
                            self.need(Tok::Name)?;
                        }
                        bindings.push(ArmBinding {
                            name: self.sym(tok),
                            pos: tok.pos,
                        });
                        if self.kind() == Tok::LParen {
                            let t = self.peek();
                            return self.fail(t, "patterns cannot be nested; bind the outer payload, then handle it in a separate match or helper function");
                        }
                        if !self.take(Tok::Comma) {
                            break;
                        }
                        if self.kind() == Tok::RParen {
                            break;
                        }
                    }
                    self.need(Tok::RParen)?;
                }
            }
            let id = self.id();
            let mut arm = Arm {
                id,
                pos: start.pos,
                path,
                bindings,
                body: Vec::new(),
                value: None,
                from_if: false,
                chain: false,
                bare,
            };
            self.value_arm(&mut arm)?;
            arms.push(arm);
        }
        self.need(Tok::Dedent)?;
        Ok(arms)
    }

    /// An arm's final expression supplies its value; a statement-only arm yields Unit.
    fn value_arm(&mut self, a: &mut Arm) -> PResult<()> {
        let (outer, outer_return) = (self.inline_statement, self.inline_return);
        let r = self.value_arm_inner(a);
        self.inline_statement = outer;
        self.inline_return = outer_return;
        r
    }

    fn value_arm_inner(&mut self, a: &mut Arm) -> PResult<()> {
        self.inline_return = false;
        self.need(Tok::Colon)?;
        let indented = self.take(Tok::Newline);
        if indented {
            self.need(Tok::Indent)?;
        }
        self.inline_statement = !indented;
        loop {
            self.statements(true, &mut a.body)?;
            if !indented {
                break;
            }
            self.newlines();
            if self.kind() == Tok::Dedent || self.kind() == Tok::Eof {
                break;
            }
        }
        if matches!(a.body.last().map(|s| &s.kind), Some(StmtKind::Call(_)))
            && let Some(Stmt {
                kind: StmtKind::Call(e),
                ..
            }) = a.body.pop()
        {
            a.value = Some(e);
        }
        for s in &a.body {
            if let StmtKind::Call(e) = &s.kind {
                let is_try = matches!(
                    e.kind,
                    ExprKind::Unary {
                        op: UnaryOp::Try,
                        ..
                    }
                );
                if !matches!(e.kind, ExprKind::Call { .. } | ExprKind::Match { .. }) && !is_try {
                    return Err(Box::new(Diagnostic::parse(
                        self.file,
                        s.pos,
                        "an arm value must be its final expression",
                    )));
                }
            }
        }
        if indented {
            self.need(Tok::Dedent)?;
        } else {
            self.inline_statement = false;
            self.end()?;
        }
        Ok(())
    }

    // ---- brackets ----

    /// Brackets may contain types or a value. A single name/application keeps
    /// both interpretations until name resolution identifies the receiver.
    fn bracket(&mut self, left: Expr) -> PResult<Expr> {
        let start = self.at;
        let saved_depth = self.depth;
        let mut types = None;
        // A type starts with a name, `fn` or `(`; anything else is a value.
        if starts_type(self.kind()) && self.type_bracket(start - 1) {
            self.speculative += 1;
            let r = self.type_args();
            self.speculative -= 1;
            match r {
                Ok(t) => types = Some(t),
                Err(_) => {
                    self.at = start;
                    // Unwinding restores nesting except for a failed `enter`,
                    // as deferred leave functions would.
                    let _ = saved_depth;
                }
            }
        }
        if let Some(types) = types {
            let pos = left.pos;
            let value = if types.len() == 1 {
                self.type_value(&types[0]).map(Box::new)
            } else {
                None
            };
            let types = if value.is_some() {
                self.copy_types(&types)
            } else {
                types
            };
            return Ok(self.mk(
                pos,
                ExprKind::Apply {
                    left: Box::new(left),
                    types,
                    value,
                },
            ));
        }
        let index = self.expression(0)?;
        if self.kind() == Tok::Colon {
            let t = self.peek();
            return self.fail(
                t,
                "there is no slice syntax; call slice(start: 0, end: 2) on a List or String",
            );
        }
        self.need(Tok::RBracket)?;
        let pos = left.pos;
        Ok(self.mk(
            pos,
            ExprKind::Index {
                left: Box::new(left),
                index: Box::new(index),
            },
        ))
    }

    /// Reinterprets a type as the value expression that spells it.
    fn type_value(&mut self, t: &TypeRef) -> Option<Expr> {
        let TypeKind::Named { name, args } = &t.kind else {
            return None;
        };
        let table = self.names;
        let mut names = table.str(*name).split('.');
        let first = names.next().unwrap_or("");
        let mut e = self.mk(t.pos, ExprKind::Name(self.names.intern(first)));
        let token = self.tokens.partition_point(|k| k.pos.offset < t.pos.offset);
        for (index, part) in names.enumerate() {
            let pos = self.tokens[token + 2 * (index + 1)].pos;
            e = self.mk(
                pos,
                ExprKind::Member {
                    left: Box::new(e),
                    name: self.names.intern(part),
                },
            );
        }
        if !args.is_empty() {
            let types = self.copy_types(args);
            let value = if args.len() == 1 {
                self.type_value(&args[0]).map(Box::new)
            } else {
                None
            };
            e = self.mk(
                t.pos,
                ExprKind::Apply {
                    left: Box::new(e),
                    types,
                    value,
                },
            );
        }
        Some(e)
    }

    /// The two bracket interpretations own their nodes independently.
    fn copy_types(&mut self, types: &[TypeRef]) -> Vec<TypeRef> {
        types.iter().map(|t| self.copy_type(t)).collect()
    }

    fn copy_type(&mut self, t: &TypeRef) -> TypeRef {
        let id = self.id();
        let kind = match &t.kind {
            TypeKind::Named { name, args } => TypeKind::Named {
                name: *name,
                args: self.copy_types(args),
            },
            TypeKind::Fn { params, result } => TypeKind::Fn {
                params: params
                    .iter()
                    .map(|p| {
                        let id = self.id();
                        Param {
                            id,
                            pos: p.pos,
                            name: p.name,
                            ty: p.ty.as_ref().map(|t| self.copy_type(t)),
                            default: p.default.clone(),
                            mutable: p.mutable,
                        }
                    })
                    .collect(),
                result: Box::new(self.copy_type(result)),
            },
        };
        TypeRef {
            id,
            pos: t.pos,
            kind,
        }
    }

    /// Preserve the historical wrapper path for expressions whose lexical
    /// error depends on its physical closing parenthesis.
    fn interpolation_wrapped(&mut self, token: Token, at: usize, source: &str) -> PResult<Expr> {
        let full = self.text(token);
        let suffix = format!(
            " ('{{' at column {} starts an interpolation; write \\{{ and \\}} for literal braces)",
            text_pos(token.pos, full, at - 1, self.boundaries).column
        );
        let wrapped = format!("({source})");
        let shift = |p: Pos| -> Pos {
            text_pos(
                token.pos,
                full,
                at - 1 + (p.offset as usize).min(source.len() + 1),
                self.boundaries,
            )
        };
        let mut lexed = match lex(self.file, &wrapped) {
            Ok(l) => l,
            Err(mut d) => {
                d.pos = shift(d.pos);
                d.end = d.end.map(shift);
                if let Some(fix) = &mut d.fix {
                    fix.pos = shift(fix.pos);
                    fix.end = shift(fix.end);
                }
                d.message.push_str(&suffix);
                return Err(d);
            }
        };
        let closing = lexed.tokens.len() - 3;
        lexed.tokens.remove(closing);
        lexed.tokens.remove(0);
        for t in &mut lexed.tokens {
            t.pos = shift(t.pos);
            t.end = shift(t.end);
        }
        let origin = self.source_origin + token.lo as usize + at - 1;
        let mut nested = Parser::new(
            self.file,
            &lexed.source,
            lexed.tokens,
            self.boundaries,
            origin,
            self.depth,
            self.next_id,
        );
        let result: PResult<Expr> = (|| {
            let value = nested.expression(0)?;
            nested.newlines();
            nested.need(Tok::Eof)?;
            Ok(value)
        })();
        self.next_id = nested.next_id;
        match result {
            Ok(v) => Ok(v),
            Err(mut d) => {
                d.message.push_str(&suffix);
                Err(d)
            }
        }
    }
}

/// Reports whether `e` is a name or member access over names.
fn plain_chain(e: &Expr) -> bool {
    let mut e = e;
    loop {
        match &e.kind {
            ExprKind::Member { left, .. } => e = left,
            ExprKind::Index { left, index } if plain_index(index) => e = left,
            ExprKind::Apply {
                left,
                types,
                value: Some(index),
            } if types.len() == 1 && plain_index(index) => e = left,
            _ => return matches!(e.kind, ExprKind::Name(_)),
        }
    }
}

/// Whether `left[index] op= value` is accepted: both parts can be evaluated twice without effect.
pub(crate) fn plain_index_target(left: &Expr, index: &Expr) -> bool {
    plain_chain(left) && plain_index(index)
}

/// The member name of an index assignment; no source name can spell it.
pub const INDEX_SET: &str = "[]=";

/// The receiver and index of `left[index]`, however the bracket was parsed.
fn index_parts(e: &Expr) -> Option<(&Expr, &Expr)> {
    match &e.kind {
        ExprKind::Index { left, index } => Some((left, index)),
        ExprKind::Apply {
            left,
            types,
            value: Some(index),
        } if types.len() == 1 => Some((left, index)),
        _ => None,
    }
}

/// An index that can be evaluated twice without effect: a name, a number or a text literal.
fn plain_index(e: &Expr) -> bool {
    match &e.kind {
        ExprKind::Name(_) | ExprKind::Number(_) => true,
        ExprKind::Member { left, .. } => plain_index(left),
        ExprKind::Text(parts) => parts.iter().all(|p| !matches!(p, TextPart::Interp(_))),
        _ => false,
    }
}

/// Spells a type's parameters as the arguments of its impl receiver.
fn type_param_names(names: Names, params: &[TypeParam]) -> String {
    if params.is_empty() {
        return String::new();
    }
    let list: Vec<&str> = params.iter().map(|p| names.str(p.name)).collect();
    format!("[{}]", list.join(", "))
}
