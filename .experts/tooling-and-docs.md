# Tooling and documentation lessons

### Standard declarations are source that tools must navigate

Decision: the user asked to keep standard type definitions in Manuscript so editor tooling can use them. Verified architecture: `stdlib/*.ms` supplies public schemas and signatures; `bindings.json` maps identities to native dispatch. Generated documentation and navigation consume this source-backed contract.

Apply when: adding standard APIs, changing their signatures, or extending hover/navigation/documentation.
Evidence: [source-definition request](codex://threads/01a12ce1-c9ff-70e4-bb2c-51749183e03b); [declaration ownership](../stdlib/README.md); [embedded sources](../stdlib/sources.go); [documentation generator](../cmd/docgen/main.go).
Verify: native calling signatures agree with the declarations, editor definitions reach the declaration, and generated references pass the existing freshness check. Update the source or generator when output changes.

### Teach a runnable path before formal reference

Decision: simplify the reading path, explain one concept at a time, and give each exact rule one home. A basic destructuring example should not require the reader to understand parallel work and error propagation. The docs revamp requested simpler explanations without losing precise semantics.

Apply when: adding tutorials, revising design chapters, or explaining new syntax.
Evidence: [documentation simplification discussion](codex://threads/01a12bf3-438d-7c72-a846-7443cea58e3a); [clarity and duplication request](codex://threads/01a12ae0-579b-7890-89d4-c0091474a2f5); [learn index](../design/learn/_index.md).
Verify: run the displayed source and commands with the stated prerequisites; check that the reading path introduces dependencies before using them. Build the book with its current strict checks and link to canonical rules instead of repeating them.

### User tooling must work in the shipped binary

Decision: documentation generation was requested as an `ms` subcommand for users, rather than only a repository generator. Native builds were subsequently requested to work from a single binary without separately installing Go, with CGO excluded. This establishes a delivery boundary for user-facing tooling: test the command from the user's installation context.

Apply when: adding CLI tooling or making claims about installation requirements.
Evidence: [ms doc request](codex://threads/01a12d4a-0182-7672-aa00-53f2bdfde033); [native build contract](../design/compiler/builds/reproducibility.md); [payload construction](../scripts/mktoolchain/main.go); [standalone distribution checks](../scripts/distcheck/main.go).
Verify: exercise a copied binary outside the checkout with empty caches, no Go on PATH, and package downloads disabled. Include ordinary/debug builds and profiling so the reduced payload covers emitted runtime references. Confirm actual external prerequisites for tools such as Delve separately; do not generalize one command's prerequisites to all tooling.

### Polish the documentation design without expanding its prose

Decision: for the documentation redesign, the user selected Tailwind CSS and Vercel as visual references and explicitly asked, “don't just randomly keep adding text.” Favor consistent navigation, typography, spacing, and reading layouts; preserve authored explanations rather than introducing promotional copy to fill the page.

Apply when: redesigning the documentation shell or overview, or extending its visual system.
Evidence: the user's documentation redesign correction; [Tailwind docs](https://tailwindcss.com/docs/installation/using-vite); [Vercel docs](https://vercel.com/docs); [site-owned visual system](../assets/_custom.scss); [overview presentation](../layouts/_shortcodes/docs-home.html).
Verify: compare authored Markdown with the base branch, keep semantic changes out of visual work, check desktop and mobile reading pages, and run the strict Hugo build with a repository URL prefix. Regenerate `docs/` from the current sources; never resolve generated-page conflicts by retaining stale output.
