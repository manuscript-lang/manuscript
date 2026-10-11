# Manuscript

The [design guide](design/_index.md) describes the Manuscript language, runtime, compiler, and developer tooling.

## Read the design book

The Markdown guides are rendered directly with [Hugo](https://gohugo.io/) and the [Hugo Book theme](https://github.com/alex-shpak/hugo-book). Install Hugo Extended 0.146 or newer.

```sh
hugo server --bind 127.0.0.1 --port 4000 --renderToMemory
```

Open <http://localhost:4000> to browse the chapters, search the book, and follow links between concepts. The preview listens only on your computer and reloads when you edit the guides. Mermaid diagrams use the theme's bundled local runtime.

```sh
hugo --minify
```

The static site is generated in `public/`. Hugo reads the Markdown guides in `design/` directly. Chapter indexes use `_index.md`; each page's front matter sets its title and reading-order weight. New Markdown pages appear automatically. Site settings live in `hugo.toml`.

Hugo Book v13 is vendored in `themes/hugo-book/`, including its MIT license. The exact upstream revision is recorded in `themes/hugo-book/UPSTREAM`.
