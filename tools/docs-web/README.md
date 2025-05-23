# Manuscript Documentation Website

This directory contains the Hugo-based documentation website for the Manuscript programming language.

## Structure

```
tools/docs-web/
├── hugo.toml              # Hugo configuration
├── content/               # Markdown content files
│   ├── _index.md         # Homepage
│   ├── docs/             # Documentation section
│   │   ├── _index.md     # Docs landing page
│   │   ├── getting-started/
│   │   ├── constructs/   # Language constructs
│   │   ├── tools/        # Development tools
│   │   ├── examples/     # Code examples
│   │   ├── tutorials/    # Tutorials
│   │   └── best-practices/
│   ├── downloads/        # Download section
│   └── community/        # Community section
├── themes/manuscript/    # Custom Hugo theme
├── static/               # Static assets
├── layouts/              # Custom layouts (if needed)
├── data/                 # Data files
└── archetypes/           # Content templates
```

## Building the Website

### Prerequisites

- Hugo (extended version) installed globally
- No additional dependencies required

### Build Commands

From the project root directory:

```bash
# Build the documentation website
make build-docs

# Serve locally for development
make serve-docs

# Clean build artifacts
make clean-docs

# Build everything including docs
make build-all
```

The built website will be available in `build/docs-web/`.

### Development

To develop the documentation:

1. Start the development server:
   ```bash
   make serve-docs
   ```

2. Open http://localhost:1313 in your browser

3. Edit content files in `content/` - Hugo will automatically reload

### Adding Content

#### New Documentation Page

```bash
cd tools/docs-web
hugo new docs/section/page-name.md
```

#### New Blog Post or Tutorial

```bash
cd tools/docs-web
hugo new docs/tutorials/tutorial-name.md
```

### Theme Customization

The custom `manuscript` theme is located in `themes/manuscript/`. Key files:

- `layouts/_default/baseof.html` - Base template
- `layouts/_default/single.html` - Single page template
- `layouts/_default/list.html` - List page template
- `layouts/index.html` - Homepage template
- `layouts/partials/` - Reusable components
- `static/css/style.css` - Stylesheet

### Configuration

Main configuration is in `hugo.toml`. Key settings:

- `baseURL` - Production website URL
- `theme` - Theme name (manuscript)
- `menu` - Navigation menu structure
- `params` - Site parameters and GitHub integration

## Deployment

The website is built to `build/docs-web/` and can be deployed to any static hosting service:

- GitHub Pages
- Netlify
- Vercel
- AWS S3 + CloudFront
- Any web server

## Content Guidelines

- Use clear, concise language
- Include code examples where appropriate
- Follow the existing structure and style
- Add appropriate front matter to new pages
- Use relative links for internal navigation 