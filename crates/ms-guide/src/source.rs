//! Source text with a lazily lexed token list, for recovering written default
//! expressions and leading comments.

use ms_syntax::token::Tok;
use std::cell::OnceCell;
use std::sync::Arc;

/// One module's source.
pub struct Source {
    text: Arc<str>,
    tokens: OnceCell<Option<Vec<(Tok, usize)>>>,
}

impl Source {
    /// Wraps source text.
    pub fn new(text: Arc<str>) -> Source {
        Source {
            text,
            tokens: OnceCell::new(),
        }
    }

    /// The text.
    pub fn text(&self) -> &str {
        &self.text
    }

    /// Token kinds with original start offsets; `None` when the source does not lex.
    pub fn tokens(&self) -> Option<&[(Tok, usize)]> {
        self.tokens
            .get_or_init(|| {
                let file: Arc<str> = Arc::from("documentation.ms");
                let lexed = ms_syntax::lexer::lex(&file, &self.text).ok()?;
                Some(
                    lexed
                        .tokens
                        .iter()
                        .map(|t| (t.kind, t.pos.offset as usize))
                        .collect(),
                )
            })
            .as_deref()
    }
}

/// The contiguous block of `#` comment lines that ends on the line directly
/// above the declaration containing `offset`. A blank line detaches the block.
/// Markers are removed; text is otherwise preserved.
pub fn leading_comment(source: &str, offset: usize) -> String {
    if offset > source.len() || !source.is_char_boundary(offset) {
        return String::new();
    }
    let before = &source[..offset];
    let mut lines: Vec<&str> = before.split('\n').collect();
    let own_line = lines.pop().unwrap_or("");
    // Names of cases and operations follow their keyword; inline payload fields
    // do not begin a declaration line and must not inherit a case description.
    if !matches!(own_line.trim(), "" | "export" | "fn" | "var fn" | "case") {
        return String::new();
    }
    let indent = |s: &str| s.len() - s.trim_start_matches([' ', '\t']).len();
    let want = indent(own_line);
    let mut block: Vec<&str> = Vec::new();
    for line in lines.iter().rev() {
        if indent(line) != want {
            break;
        }
        let line = line.trim();
        let Some(rest) = line.strip_prefix('#') else {
            break;
        };
        block.push(rest.strip_prefix(' ').unwrap_or(rest));
    }
    block.reverse();
    block.join("\n")
}
