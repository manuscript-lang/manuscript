//! Effect directives: `// ms: effect NAME` declares an effect a function performs, and
//! `// ms: allow_effect PATTERN` permits effects a function (or, in a file's header comment,
//! every function in the file) may reach. See `proposals/function-effects.md`.

/// The directive lines found in one comment block.
#[derive(Default, Clone, Debug, PartialEq, Eq)]
pub struct Directives {
    /// `// ms: effect NAME`: effects the function declares.
    pub declared: Vec<String>,
    /// `// ms: allow_effect PATTERN`: permissions; `None` when no line was written, so an
    /// absent scope is distinct from an empty one.
    pub allow: Option<Vec<String>>,
}

impl Directives {
    fn line(&mut self, text: &str) {
        let Some(rest) = text.trim().strip_prefix("// ms:") else {
            return;
        };
        let rest = rest.trim();
        if let Some(name) = rest.strip_prefix("allow_effect ") {
            self.allow
                .get_or_insert_with(Vec::new)
                .push(name.trim().to_string());
        } else if let Some(name) = rest.strip_prefix("effect ") {
            self.declared.push(name.trim().to_string());
        }
    }
}

/// The comment lines of a source file, for header and per-declaration lookups.
pub struct Lines<'a> {
    lines: Vec<&'a str>,
}

impl<'a> Lines<'a> {
    /// Indexes the lines of `source` (CR stripped).
    pub fn new(source: &'a str) -> Lines<'a> {
        Lines {
            lines: source
                .split('\n')
                .map(|l| l.trim_end_matches('\r'))
                .collect(),
        }
    }

    /// The file header: `//` lines at the top of the file, ended by a blank line. A comment block
    /// that runs straight into code belongs to that declaration, not to the file.
    pub fn header(&self) -> Directives {
        let mut found = Directives::default();
        let comments = self
            .lines
            .iter()
            .take_while(|l| l.trim_start().starts_with("//"))
            .count();
        if comments == 0
            || self
                .lines
                .get(comments)
                .is_none_or(|l| !l.trim().is_empty())
        {
            return found;
        }
        for line in &self.lines[..comments] {
            found.line(line);
        }
        found
    }

    /// The `//` lines directly above the 1-based `line`, up to a blank or code line.
    pub fn above(&self, line: u32) -> Directives {
        let mut found = Directives::default();
        let mut at = (line as usize).saturating_sub(1);
        while at > 0 && self.lines[at - 1].trim_start().starts_with("//") {
            found.line(self.lines[at - 1]);
            at -= 1;
        }
        found
    }
}

/// Whether `effect` matches `pattern`: `*` matches everything, `a.b.*` a prefix, `*.write` a last
/// segment, and any other pattern only itself.
pub fn matches(pattern: &str, effect: &str) -> bool {
    if pattern == "*" {
        return true;
    }
    if let Some(prefix) = pattern.strip_suffix(".*") {
        return effect
            .strip_prefix(prefix)
            .is_some_and(|rest| rest.starts_with('.'));
    }
    if let Some(suffix) = pattern.strip_prefix("*.") {
        return effect
            .rsplit_once('.')
            .is_some_and(|(_, last)| last == suffix);
    }
    pattern == effect
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn patterns() {
        assert!(matches("*", "std.fs.read"));
        assert!(matches("std.fs.*", "std.fs.read"));
        assert!(!matches("std.fs.*", "std.fsx.read"));
        assert!(!matches("std.fs.*", "std.fs"));
        assert!(matches("*.read", "std.fs.read"));
        assert!(!matches("*.read", "std.fs.write"));
        assert!(matches("db.write", "db.write"));
        assert!(!matches("db.write", "db.writes"));
    }

    #[test]
    fn header_needs_a_blank_line() {
        let src = include_str!("../tests/effects/header_blank.ms");
        let lines = Lines::new(src);
        assert_eq!(lines.header().allow, Some(vec!["std.fs.read".to_string()]));
        assert_eq!(lines.above(3).allow, None);
        let src = include_str!("../tests/effects/header_adjacent.ms");
        let lines = Lines::new(src);
        assert_eq!(lines.header().allow, None);
        assert_eq!(lines.above(2).allow, Some(vec!["std.fs.read".to_string()]));
    }

    #[test]
    fn declared_and_allowed_lines() {
        let src = include_str!("../tests/effects/declared.ms");
        let found = Lines::new(src).above(4);
        assert_eq!(found.declared, vec!["db.write".to_string()]);
        assert_eq!(found.allow, Some(vec!["std.net.connect".to_string()]));
    }
}
