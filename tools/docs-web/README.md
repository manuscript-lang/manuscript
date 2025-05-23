# Manuscript Documentation Website

This directory contains the Hugo-based documentation website for the Manuscript programming language, built using the [Docsy](https://www.docsy.dev/) theme via Hugo modules.

## Structure

```
tools/docs-web/
├── hugo.toml              # Hugo configuration
├── go.mod                 # Hugo modules configuration
├── go.sum                 # Hugo modules checksums
├── content/               # Markdown content files
│   ├── _index.md         # Homepage
│   ├── docs/             # Documentation section
│   │   ├── _index.md     # Docs landing page
│   │   ├── getting-started/
│   │   ├── constructs/   # Language constructs
│   │   ├── tools/        # Development tools
│   │   ├── examples/     # Code examples
│   │   ├── tutorials/    # Tutorials
│   └── community/        # Community section
├── static/               # Static assets
├── layouts/              # Custom layouts (if needed)
├── data/                 # Data files
└── archetypes/           # Content templates
```

## Building the Website

### Prerequisites

- Hugo (extended version 0.75.0 or later) installed globally
- Go (for Hugo modules)
- No additional theme installation required - Docsy is downloaded automatically via Hugo modules

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

### Hugo Modules

This site uses Hugo modules to manage the Docsy theme and its dependencies. The modules are configured in:

- `go.mod` - Defines the module dependencies
- `hugo.toml` - Contains the module import configuration

To update the Docsy theme:

```bash
cd tools/docs-web
hugo mod get -u github.com/google/docsy
hugo mod tidy
```

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

The site uses the [Docsy](https://www.docsy.dev/) theme. Customizations can be made by:

- Adding custom CSS in `assets/scss/_custom.scss` 
- Creating custom layouts in `layouts/` to override Docsy's defaults
- Adding custom partials in `layouts/partials/`
- Configuring theme parameters in `hugo.toml`

For more information, see the [Docsy documentation](https://www.docsy.dev/docs/).

### Configuration

Main configuration is in `hugo.toml`. Key settings:

- `baseURL` - Production website URL
- `module` - Hugo modules configuration for Docsy
- `menu` - Navigation menu structure
- `params` - Site parameters including Docsy theme configuration
- `params.github` - GitHub integration settings

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
- Follow [Docsy's content guidelines](https://www.docsy.dev/docs/adding-content/) where applicable 