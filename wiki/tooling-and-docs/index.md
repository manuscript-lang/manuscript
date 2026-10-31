[Wiki](../index.md) › Tooling and docs

# Tooling and docs

Formatter, LSP, CLI, diagnostics, documentation, site.

- [Bound navigation coordinate work to the query](bound-navigation-coordinate-work-to-the-query.md): avoid repeated prefix scans while preserving malformed snapshots and early-reference costs.

- [Agent help is CLI commands, not a protocol server](agent-help-is-cli-commands-not-a-protocol-server.md): the user evaluated an MCP server (PR #528), judged the CLI the better surface for coding agents, and had it removed.
- [Agents get machine-applicable fixes, structured faults and named replacements](agents-get-machine-applicable-fixes-structured-faults-and-na.md): diagnostics carry a `fix` field when the repair is mechanical (nearest-name misspellings, missing imports), and `ms check --fix` / `ms lint…
- [Diagnostics are `<cause>; <fix>`, and tools key on the cause](diagnostics-are-cause-fix-and-tools-key-on-the-cause.md): agents act on a diagnostic only when it names the cause, the location, and a concrete fix (nearest name, import line, valid options).
- [Editor recovery must preserve delimiter continuations](editor-recovery-must-preserve-delimiter-continuations.md): strict parsing accepts multiline parameters, but declaration recovery that splits their column-zero closing delimiters into separate chunks…
- [Recovered navigation needs local header ranges](recovered-navigation-needs-local-header-ranges.md): a malformed neighbor must not move declaration names to their keyword positions.
- [Keep CLI and HTTP documentation with their packages](keep-cli-and-http-documentation-with-their-packages.md): the user explicitly removed the "Application hosts" section.
- [Polish the documentation design without expanding its prose](polish-the-documentation-design-without-expanding-its-prose.md): the user selected Tailwind CSS and Vercel as documentation design references and asked not to add filler.
- [Preserve OS argument identity before dispatch](preserve-os-argument-identity-before-dispatch.md): lossy conversion can select an existing replacement-character filename instead of the requested byte path.
- [Profile native programs by Manuscript position](profile-native-programs-by-manuscript-position.md): `ms profile` replaces the debugger (the debugger and DAP are dropped).
- [Project review must keep library internals behind their boundary](project-review-must-keep-library-internals-behind-their-boun.md): inspection deliberately includes bundled standard source modules.
- [Readable formatting needs paragraphs while retaining inline guards](readable-formatting-needs-paragraphs-while-retaining-inline.md): the user's formatter request keeps inline `if` bodies and introduces natural reading boundaries around declarations, guard sections, substan…
- [Select boundaries before scanning default ranges](select-boundaries-before-scanning-default-ranges.md): avoid multiplying discarded EOF scans when choosing outline ranges.
- [Sell the language through a story and concrete proof](sell-the-language-through-a-story-and-concrete-proof.md): preserve the prominent tagline, “The language for the agentic era.”, and lead with agents writing correct, fast programs that are easy to review.
- [Shared editor analysis must preserve selected roots and overlays](shared-editor-analysis-must-preserve-selected-roots-and-over.md): resolve the nearest manifest before sharing analysis.
- [Signature labels follow checked callees](signature-labels-follow-checked-callees.md): use checked callee spans and retain grouped receiver boundaries inside interpolation.
- [Source freshness does not establish published freshness](source-freshness-does-not-establish-published-freshness.md): after the concurrency simplification, source declarations and generated Markdown were current while the checked-in website still exposed ret…
- [Standard declarations are source that tools must navigate](standard-declarations-are-source-that-tools-must-navigate.md): the user asked to keep standard type definitions in Manuscript so editor tooling can use them.
- [Standard-library prose has the same owner as declarations](standard-library-prose-has-the-same-owner-as-declarations.md): the user requires `.ms` standard-library sources to own all library documentation.
- [Stream coordinates for ordered token batches](stream-coordinates-for-ordered-token-batches.md): keep an exact boundary anchor to avoid repeated UTF-16 prefix work without changing exceptional offsets.
- [Teach a runnable path before formal reference](teach-a-runnable-path-before-formal-reference.md): public documentation should focus on Manuscript and what readers can build.
- [User tooling must work in the shipped binary](user-tooling-must-work-in-the-shipped-binary.md): documentation generation was requested as an `ms` subcommand for users, rather than only a repository generator.
- [Stdout errors include the final flush](stdout-errors-include-final-flush.md): small buffered writes and large direct writes fail at different points; neither failure may silently become a successful command.
