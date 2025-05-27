---
title: "Configuration"
description: "Manuscript compiler configuration options and file formats"
weight: 60
---

The Manuscript compiler supports configuration through YAML and JSON files to customize compilation behavior. Configuration files allow you to specify output directories, entry files, and other compilation options.

## Configuration Files

### Supported Formats

The compiler supports configuration files in YAML and JSON formats:

- **YAML**: `ms.yml` or `ms.yaml`
- **JSON**: `ms.json`

### File Discovery

The compiler searches for configuration files in the following order:

1. **Environment Variable**: If `MS_CONFIG_FILE` is set, it uses that file path
2. **Explicit Path**: If a path is provided to the compiler via `--config` flag
3. **Automatic Discovery**: Searches for `ms.yml`, `ms.yaml`, or `ms.json` starting from the current directory and walking up the directory tree

**Note**: Automatic discovery looks for specifically named files (`ms.yml`, `ms.yaml`, or `ms.json`). Other JSON configuration files (like `config.json`) must be explicitly specified using the `--config` flag or `MS_CONFIG_FILE` environment variable.

### Configuration Structure

Configuration files use a nested structure with a `compilerOptions` section:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `compilerOptions.outputDir` | string | `"./build"` | Directory where compiled Go files will be written |
| `compilerOptions.entryFile` | string | `""` | Main entry file for the application |

## Configuration File Examples

### YAML Configuration (`ms.yml`)

```yaml
# Manuscript compiler configuration
compilerOptions:
  outputDir: ./dist
  entryFile: main.ms
```

### JSON Configuration (`ms.json`)

```json
{
  "compilerOptions": {
    "outputDir": "./dist",
    "entryFile": "main.ms"
  }
}
```

## Environment Variables

### MS_CONFIG_FILE

You can specify the configuration file location using the `MS_CONFIG_FILE` environment variable:

```bash
export MS_CONFIG_FILE=/path/to/custom-config.yml
msc build main.ms
```

This environment variable takes precedence over any path provided to the compiler.

## Usage Examples

### Basic Usage with Entry File

Create a `ms.yml` file in your project root:

```yaml
compilerOptions:
  outputDir: ./build
  entryFile: src/main.ms
```

Then run the compiler using the entry file from config:

```bash
msc build
```

Or build a specific file (overrides config entry file):

```bash
msc build main.ms
```

### Custom Configuration File

Use a custom configuration file:

```bash
msc build --config custom-config.yml main.ms
```

Or set it via environment variable:

```bash
export MS_CONFIG_FILE=custom-config.yml
msc build main.ms
```

### Override Output Directory

You can override the output directory without a config file:

```bash
msc build --outdir ./custom-output main.ms
```

**Note**: The `--config` and `--outdir` flags cannot be used together.

### Directory Structure

```
my-project/
├── ms.yml              # Configuration file
├── src/
│   ├── main.ms         # Entry file
│   └── utils.ms
└── build/              # Output directory
    ├── main.go
    └── utils.go
```

## Command Line Interface

### Build Command

```bash
# Build using entryFile from configuration
msc build

# Build specific file (overrides config entryFile)
msc build [options] <file.ms>
```

**Options:**
- `--config <path>`: Path to configuration file (YAML or JSON)
- `--outdir <path>`: Output directory (cannot be used with `--config`)
- `-d`: Enable debug mode (print token stream)

**Behavior:**
1. **`msc build`** - Looks for configuration file (`ms.yml`, `ms.yaml`, or `ms.json`) and uses the `entryFile` specified in the configuration. If no `entryFile` is defined, an error is displayed.
2. **`msc build file.ms`** - Uses the specified file as the entry point, with CLI arguments taking highest precedence over configuration settings.

### Run Command

```bash
msc <file.ms>
```

Compiles and outputs the Go code to stdout without writing files.

## Configuration Precedence

Configuration is loaded with the following precedence (highest to lowest):

1. **Command Line Flags**: `--outdir` overrides config file settings
2. **Environment Variable**: `MS_CONFIG_FILE` specifies config file location
3. **Explicit Path**: Path provided via `--config` command line argument
4. **Auto-discovery**: `ms.yml`, `ms.yaml`, or `ms.json` found in current or parent directories
5. **Default Values**: Built-in defaults if no configuration is found

## Validation

The compiler validates configuration options:

- `outputDir` cannot be empty
- File paths are resolved relative to the configuration file location

## Best Practices

### Project Configuration

- Place `ms.yml` in your project root
- Use relative paths for `outputDir` and `entryFile`
- Commit configuration files to version control

### Environment-Specific Configuration

For different environments, use the `MS_CONFIG_FILE` environment variable:

```bash
# Development
export MS_CONFIG_FILE=config/dev.yml

# Production
export MS_CONFIG_FILE=config/prod.yml
```

### Configuration Templates

**Development** (`config/dev.yml`):
```yaml
compilerOptions:
  outputDir: ./build/dev
  entryFile: src/main.ms
```

**Production** (`config/prod.yml`):
```yaml
compilerOptions:
  outputDir: ./dist
  entryFile: src/main.ms
```
