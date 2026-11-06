//! A project function reaches an effect no `// ms: allow_effect` line permits (`MSL116`). A
//! function with no directive is pure: reaching `std.fs.write` or `std.console.write` is a
//! finding at the first reference that brings the effect in. See `proposals/function-effects.md`.

use super::{Finding, finding};
use ms_check::Program;
use std::sync::Arc;

pub(super) fn lint(syms: ms_syntax::Names, program: &Program, findings: &mut Vec<Finding>) {
    for v in &program.effect_violations {
        let file: Arc<str> = Arc::from(syms.str(v.file));
        let root = v.path.first().map_or("this function", String::as_str);
        let message = if v.path.len() > 1 {
            format!(
                "`{root}` reaches {}: {}; permit it with `// ms: allow_effect {}`, move the call to the caller, or take a capability parameter",
                v.effect,
                v.path.join(" -> "),
                v.effect
            )
        } else {
            format!(
                "`{root}` reaches {}; permit it with `// ms: allow_effect {}`, move the call to the caller, or take a capability parameter",
                v.effect, v.effect
            )
        };
        findings.push(finding("MSL116", message, &file, v.pos));
    }
}
