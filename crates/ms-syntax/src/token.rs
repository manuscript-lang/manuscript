//! Token kinds produced by the lexer.

use crate::pos::Pos;

macro_rules! tokens {
    ($($variant:ident => $text:expr),* $(,)?) => {
        /// Token kind. Layout tokens (`Newline`, `Indent`, `Dedent`, `Eof`)
        /// have empty text; keywords and punctuation are their own spelling.
        #[derive(Copy, Clone, Debug, PartialEq, Eq, Hash)]
        pub enum Tok { $($variant),* }
        impl Tok {
            /// The kind's name string.
            pub fn as_str(self) -> &'static str {
                match self { $(Tok::$variant => $text),* }
            }
        }
    };
}

tokens! {
    Comment => "#comment",
    Newline => "NEWLINE", Indent => "INDENT", Dedent => "DEDENT", Eof => "EOF",
    Name => "NAME", Number => "NUMBER", String => "STRING",
    And => "and", Break => "break", Case => "case", Continue => "continue", Def => "def",
    Elif => "elif", Else => "else", Export => "export", Extern => "extern", False => "False", Fixture => "fixture",
    For => "for", If => "if", Impl => "impl", Import => "import", In => "in",
    Interface => "interface", Lambda => "lambda", Let => "let", Match => "match", Not => "not",
    Or => "or", Ref => "ref", Return => "return", SelfKw => "self", Test => "test", True => "True", Try => "try",
    Type => "type", Var => "var", While => "while", With => "with", Underscore => "_",
    LParen => "(", RParen => ")", LBracket => "[", RBracket => "]", LBrace => "{", RBrace => "}",
    Colon => ":", Comma => ",", Dot => ".", Plus => "+", Minus => "-", Star => "*", Slash => "/",
    Percent => "%", Lt => "<", Gt => ">", Assign => "=", Amp => "&", Pipe => "|", Ellipsis => "...",
    Arrow => "->", EqEq => "==", NotEq => "!=", Le => "<=", Ge => ">=",
}

impl Tok {
    /// Maps an identifier-shaped word to its keyword kind, or `Name`.
    pub fn from_word(word: &str) -> Tok {
        match word {
            "False" => Tok::False,
            "True" => Tok::True,
            "and" => Tok::And,
            "break" => Tok::Break,
            "case" => Tok::Case,
            "continue" => Tok::Continue,
            "def" => Tok::Def,
            "elif" => Tok::Elif,
            "else" => Tok::Else,
            "export" => Tok::Export,
            "extern" => Tok::Extern,
            "fixture" => Tok::Fixture,
            "for" => Tok::For,
            "if" => Tok::If,
            "impl" => Tok::Impl,
            "import" => Tok::Import,
            "in" => Tok::In,
            "interface" => Tok::Interface,
            "lambda" => Tok::Lambda,
            "let" => Tok::Let,
            "match" => Tok::Match,
            "not" => Tok::Not,
            "or" => Tok::Or,
            "ref" => Tok::Ref,
            "return" => Tok::Return,
            "self" => Tok::SelfKw,
            "test" => Tok::Test,
            "try" => Tok::Try,
            "type" => Tok::Type,
            "var" => Tok::Var,
            "while" => Tok::While,
            "with" => Tok::With,
            "_" => Tok::Underscore,
            _ => Tok::Name,
        }
    }

    /// True for the layout tokens that have no source text.
    pub fn is_layout(self) -> bool {
        matches!(self, Tok::Newline | Tok::Indent | Tok::Dedent | Tok::Eof)
    }
}

/// The reserved words, sorted. `_` is lexed as its own
/// kind but is not in this list.
pub const KEYWORDS: &[&str] = &[
    "False",
    "True",
    "and",
    "break",
    "case",
    "continue",
    "def",
    "elif",
    "else",
    "export",
    "extern",
    "fixture",
    "for",
    "if",
    "impl",
    "import",
    "in",
    "interface",
    "lambda",
    "let",
    "match",
    "not",
    "or",
    "ref",
    "return",
    "self",
    "test",
    "try",
    "type",
    "var",
    "while",
    "with",
];

/// One token. The text is `source[lo..hi]` of the (CRLF-normalised) source the
/// lexer returned; layout tokens have an empty range.
#[derive(Copy, Clone, Debug)]
pub struct Token {
    /// Kind.
    pub kind: Tok,
    /// Start in original-source coordinates.
    pub pos: Pos,
    /// Exclusive end in original-source coordinates.
    pub end: Pos,
    /// Start of the text in the normalised source.
    pub lo: u32,
    /// End of the text in the normalised source.
    pub hi: u32,
}
