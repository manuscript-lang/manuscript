//! Edits to `ms.toml` for `ms add` and `ms remove`: they change the dependency tables and keep
//! every comment and the formatting of the rest of the file.

use toml_edit::{DocumentMut, InlineTable, Item, Table, value};

use crate::project::manifest::valid_alias;

/// How a dependency pins its source.
pub enum Pin<'a> {
    Tag(&'a str),
    Sha(&'a str),
    Version(&'a str),
}

/// The package name `ms add` gives a repository URL: its last path segment without `.git` and
/// without a leading `ms-`, so `https://github.com/acme/ms-pg.git` is `@pg`.
pub fn default_name(url: &str) -> Option<String> {
    let last = url.trim_end_matches('/').rsplit(['/', ':']).next()?;
    let base = last.strip_suffix(".git").unwrap_or(last);
    let base = base.strip_prefix("ms-").unwrap_or(base);
    let name = format!("@{}", base.replace('-', "_"));
    valid_alias(&name).then_some(name)
}

fn edit(text: &str) -> Result<DocumentMut, String> {
    text.parse::<DocumentMut>()
        .map_err(|e| format!("ms.toml is not valid TOML: {}", e.message()))
}

fn table<'a>(document: &'a mut DocumentMut, name: &str) -> Result<&'a mut Table, String> {
    let item = document
        .entry(name)
        .or_insert_with(|| Item::Table(Table::new()));
    item.as_table_mut()
        .ok_or_else(|| format!("[{name}] in ms.toml is not a table"))
}

/// `text` with `name = { url = ..., version | tag | sha = ... }` under `[dependencies]`.
pub fn add_dependency(text: &str, name: &str, url: &str, pin: &Pin<'_>) -> Result<String, String> {
    let mut document = edit(text)?;
    let dependencies = table(&mut document, "dependencies")?;
    if dependencies.contains_key(name) {
        return Err(format!(
            "{name} is already in [dependencies]; run `ms remove {name}` first, or edit its entry"
        ));
    }
    let mut entry = InlineTable::new();
    entry.insert("url", url.into());
    match pin {
        Pin::Tag(tag) => entry.insert("tag", (*tag).into()),
        Pin::Sha(sha) => entry.insert("sha", (*sha).into()),
        Pin::Version(version) => entry.insert("version", (*version).into()),
    };
    dependencies.insert(name, value(entry));
    Ok(document.to_string())
}

/// `text` allowing `name` the `effects` it declares, under `[effects]`.
pub fn allow_effects(text: &str, name: &str, effects: &[String]) -> Result<String, String> {
    let mut document = edit(text)?;
    let allowed = table(&mut document, "effects")?;
    allowed.insert(
        name,
        value(
            effects
                .iter()
                .map(String::as_str)
                .collect::<toml_edit::Array>(),
        ),
    );
    Ok(document.to_string())
}

/// `text` without `name` in `[dependencies]` and `[effects]`; an error when it was not a dependency.
pub fn remove_dependency(text: &str, name: &str) -> Result<String, String> {
    let mut document = edit(text)?;
    let found = document
        .get_mut("dependencies")
        .and_then(Item::as_table_like_mut)
        .is_some_and(|t| t.remove(name).is_some());
    if !found {
        return Err(format!("{name} is not in [dependencies]"));
    }
    if let Some(allowed) = document
        .get_mut("effects")
        .and_then(Item::as_table_like_mut)
    {
        allowed.remove(name);
        if allowed.is_empty() {
            document.remove("effects");
        }
    }
    if document
        .get("dependencies")
        .and_then(Item::as_table_like)
        .is_some_and(|t| t.is_empty())
    {
        document.remove("dependencies");
    }
    Ok(document.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    const BASE: &str = "# my app\n[project]\nname = \"app\" # the name\nsource = \"src\"\n";

    #[test]
    fn names_come_from_the_repository() {
        assert_eq!(
            default_name("https://github.com/acme/ms-pg.git").as_deref(),
            Some("@pg")
        );
        assert_eq!(
            default_name("https://github.com/acme/wire/").as_deref(),
            Some("@wire")
        );
        assert_eq!(
            default_name("https://github.com/acme/my-lib.git").as_deref(),
            Some("@my_lib")
        );
        assert_eq!(default_name("https://github.com/acme/2fast.git"), None);
    }

    #[test]
    fn add_keeps_comments_and_reads_back() {
        let added =
            add_dependency(BASE, "@pg", "https://h/x/ms-pg.git", &Pin::Tag("v1.0.0")).unwrap();
        assert!(added.starts_with("# my app\n[project]"), "{added}");
        assert!(added.contains("# the name"), "{added}");
        assert!(
            added.contains("\"@pg\" = { url = \"https://h/x/ms-pg.git\", tag = \"v1.0.0\" }"),
            "{added}"
        );
        let again = add_dependency(&added, "@pg", "https://h/x/ms-pg.git", &Pin::Tag("v2.0.0"));
        assert!(again.unwrap_err().contains("already in [dependencies]"));
    }

    #[test]
    fn allow_then_remove_leaves_the_file_as_it_was() {
        let added = add_dependency(
            BASE,
            "@pg",
            "https://h/x/ms-pg.git",
            &Pin::Sha(&"a".repeat(40)),
        )
        .unwrap();
        let allowed = allow_effects(&added, "@pg", &["std.net.*".to_string()]).unwrap();
        assert!(allowed.contains("\"@pg\" = [\"std.net.*\"]"), "{allowed}");
        let removed = remove_dependency(&allowed, "@pg").unwrap();
        assert_eq!(removed.trim_end(), BASE.trim_end());
        assert!(
            remove_dependency(&removed, "@pg")
                .unwrap_err()
                .contains("not in [dependencies]")
        );
    }
}
