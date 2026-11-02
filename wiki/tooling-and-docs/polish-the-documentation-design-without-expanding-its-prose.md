[Wiki](../index.md) › [Tooling and docs](index.md)

# Polish the documentation design without expanding its prose

Decision: the user selected Tailwind CSS and Vercel as documentation design references and asked not to add filler. The later direction makes the landing page a marketing page whose goal is getting people to try Manuscript: lead with "The language for the agentic era." as the hero headline, a runnable example, and a clear first-run action.

Apply when: redesigning the documentation shell or overview, or extending its visual system.
Evidence: the user's documentation redesign correction; [Tailwind docs](https://tailwindcss.com/docs/installation/using-vite); [Vercel docs](https://vercel.com/docs); [site-owned visual system](../../website/assets/_custom.scss); [overview presentation](../../website/layouts/_shortcodes/docs-home.html).
Verify: inspect desktop and narrow mobile renders in both themes; the first action and example remain readable with brief supporting copy. This records the requested direction; verify its implementation in the checkout being edited.
Verify: compare authored Markdown with the base branch, keep semantic changes out of visual work, check desktop and mobile reading pages, and run the strict Hugo build with a repository URL prefix (`make book-check`). Verify actual token colors in light and dark mode, unchanged copied text, and plain terminal output.
