---
title: "Configuration: Tuning Your Manuscript Compiler"
description: "A detailed guide to Manuscript compiler configuration options, file formats, environment variables, and how to tell the compiler what you want."
weight: 60 # Assuming a weight for sidebar ordering
---

Welcome to the control room! The Manuscript compiler (`msc`) is a versatile engine, and like any good engine, it can be tuned to your project's specific needs. This guide details how you can customize its compilation behavior using configuration files (in YAML or JSON flavors), environment variables, and command-line flags. Let's get your compiler humming just right.

## Configuration Files: The Instruction Manuals

You can provide the compiler with a dedicated instruction manual, a configuration file, to specify your preferences.

### Supported Formats: Speaking a Common Tongue
The compiler understands instructions written in two popular structured data formats:

- **YAML**: Look for files named `ms.yml` or `ms.yaml`. Known for its (arguably) human-friendly readability.
- **JSON**: Look for `ms.json`. Strict, precise, and beloved by machines everywhere.

### File Discovery: The Compiler's Treasure Hunt
When you ask `msc` to do something, it goes on a little hunt for its instruction manual. Here's the order in which it searches:

1.  **Environment Variable First Dibs**: If the `MS_CONFIG_FILE` environment variable is set, the compiler immediately grabs that file. No questions asked.
2.  **Explicit Command**: If you tell the compiler exactly where to look using the `--config` flag (e.g., `msc build --config my_special_config.yml`), it will dutifully obey.
3.  **Automatic Discovery Adventure**: If not told otherwise, `msc` becomes an explorer. It starts looking in the current directory for `ms.yml`, then `ms.yaml`, then `ms.json`. If it finds nothing, it peeks into the parent directory, and so on, walking up the directory tree until it finds one or gives up.

**Important Note**: This automatic discovery is a bit particular; it *only* looks for those exact filenames (`ms.yml`, `ms.yaml`, `ms.json`). If your configuration file has a more creative name like `project_config_for_tuesday.json`, you'll need to point to it explicitly using the `--config` flag or the `MS_CONFIG_FILE` environment variable.

### Configuration Structure: What Goes Inside the Manual
Your configuration file should have a main section called `compilerOptions`. Within this, you can specify various settings. Here are the current stars of the show:

| Option                      | Type   | Default     | Description                                                                 |
|-----------------------------|--------|-------------|-----------------------------------------------------------------------------|
| `compilerOptions.outputDir` | string | `"./build"` | The workshop where your compiled Go files will be neatly placed.            |
| `compilerOptions.entryFile` | string | `""`        | The main Manuscript file that kicks off your application (if applicable). |

(More options may arrive in future dispatches from Manuscript HQ!)

## Configuration File Examples: See It In Action

A picture is worth a thousand words, and an example is worth... well, at least a few hundred.

### YAML Flavor (`ms.yml`)
```yaml
# Manuscript Compiler Configuration: Instructions for Optimal Performance

compilerOptions:
  # Where the compiled Go files should land
  outputDir: ./dist  # Let's send them to 'dist' instead of 'build'

  # The main Manuscript file to start the compilation from
  entryFile: src/app_entry.ms
```

### JSON Flavor (`ms.json`)
```json
{
  "compilerOptions": {
    "outputDir": "./dist",
    "entryFile": "src/app_entry.ms"
  }
}
```
Choose the format that makes your heart sing (or that your team agrees on).

## Environment Variables: Whispering Secrets to the Compiler

Sometimes, you want to influence the compiler without writing a file, perhaps in a CI/CD pipeline or for a quick override.

### `MS_CONFIG_FILE`: The Secret Map
You can tell `msc` exactly where to find its configuration file using the `MS_CONFIG_FILE` environment variable.

```bash
# Tell msc to use a very specific config file for this session
export MS_CONFIG_FILE=/path/to/your/super_secret_project_config.yml
msc build main.ms # msc will now use that specific yml file
```
This variable is quite influential; it takes precedence over a path provided via `--config` if both are somehow present (though that would be an odd scenario).

## Usage Examples: Putting It All Together

Let's see how these configuration methods play out in common scenarios.

### Basic Usage with an Entry File in Config
Imagine your project root has this `ms.yml`:
```yaml
compilerOptions:
  outputDir: ./build
  entryFile: src/main.ms # Your main application file
```

You can then simply run:
```bash
msc build
```
`msc` will find `ms.yml`, see `src/main.ms` as the entry point, and compile it into the `./build` directory. Magic!

Want to compile a *different* file for a quick test, ignoring the `entryFile` in the config for this one command?
```bash
msc build path/to/another_file.ms
```
The command line argument for the file to build takes precedence over the `entryFile` in the config.

### Using a Custom-Named Configuration File
If your config file is named `my_project_setup.json`:
```bash
msc build --config my_project_setup.json main.ms
```
Or, using the environment variable:
```bash
export MS_CONFIG_FILE=my_project_setup.json
msc build main.ms
```

### Overriding the Output Directory On-the-Fly
No config file needed if you just want to change the output directory for a one-off build:
```bash
msc build --outdir ./temp_output_for_testing main.ms
```
**Heads Up**: You can't use `--config` and `--outdir` at the same time. The compiler would get confused about which instructions to follow for the output directory. Choose one path to output enlightenment.

### A Typical Project Directory Structure
```
my-manuscript-project/
├── ms.yml                # Your project's main configuration file
├── src/                  # Source code often lives here
│   ├── main.ms           # The entry file specified in ms.yml
│   └── helpers/
│       └── string_utils.ms # A utility module
└── build/                # Default output directory, as per ms.yml
    ├── main.go           # Compiled Go output
    └── helpers/
        └── string_utils.go # Compiled utility module
```

## Command Line Interface (CLI): Direct Orders

You can also give direct orders to `msc` via command-line arguments.

### The `build` Command: To Compile and Save
```bash
# Option 1: Rely on the configuration file (especially the entryFile)
msc build

# Option 2: Specify the entry file directly.
# This overrides entryFile from config if one exists.
msc build [options] <file.ms>
```
**Available Options for `build`:**
- `--config <path>`: Specifies the path to your configuration file (YAML or JSON).
- `--outdir <path>`: Specifies the output directory. Remember, this can't be used with `--config`.
- `-d` or `--debug`: Enables debug mode, which might print a torrent of tokens or other internal compiler states. Fascinating for the curious!

**Behavior Unpacked:**
1.  **`msc build` (no file specified):** `msc` diligently looks for a configuration file (`ms.yml`, `ms.yaml`, or `ms.json`) using its discovery adventure rules. It then *requires* an `entryFile` to be specified within that configuration. If no `entryFile` is defined in the found config, `msc` will politely inform you of this oversight with an error.
2.  **`msc build file.ms` (file specified):** `msc` uses `file.ms` as the main entry point for this particular compilation. Command-line arguments (like `--outdir` if you're not using `--config`) generally hold the highest sway over configuration settings found in files.

### The `run` Command (Conceptual Simplicity)
```bash
msc <file.ms>
# Or potentially: msc run <file.ms> (Syntax may vary)
```
This command is typically for quick tests. It compiles the specified `<file.ms>` and, instead of writing Go files to disk, it usually outputs the generated Go code directly to `stdout` (your terminal screen) or might even compile and run it in memory. It's the "quick look" version of compilation.

## The Great Configuration Precedence Battle

When `msc` finds configuration settings in multiple places, which one wins? It's a hierarchy, like a royal court:

1.  **Command Line Flags**: Arguments like `--outdir` are the King/Queen. They override almost everything else.
2.  **Environment Variable (`MS_CONFIG_FILE`)**: This is like the Hand of the King/Queen, dictating which scroll (config file) is read above all others specified by path.
3.  **Explicit Path (`--config` flag)**: The Royal Decree. If you use `--config path/to/file.yml`, that specific file is chosen.
4.  **Auto-discovery**: The Town Crier. `msc` finds `ms.yml`, `ms.yaml`, or `ms.json` in the current or parent directories.
5.  **Default Values**: The Common Lore. If no other instructions are found, `msc` uses its built-in sensible defaults (e.g., outputting to `./build`).

> Flags shout the loudest,
> Env vars then guide the path,
> Defaults wait silent.

## Validation: The Compiler's Sanity Check

The compiler isn't just a blind follower of instructions; it does some basic sanity checks on your configuration:
- `outputDir`, if specified, generally cannot be an empty string (where would the files go, into the void?).
- File paths mentioned in the configuration (like `entryFile`) are usually resolved relative to the location of the configuration file itself, not necessarily your current working directory. This keeps things predictable.

## Quartermaster's Wisdom: Best Practices for Configuration

A few tips for keeping your project configurations orderly and effective.

### Project Configuration: The Main Blueprint
- It's generally a good idea to have an `ms.yml` (or `.yaml`/`.json`) file in the root directory of your project. This becomes the single source of truth for your project's build settings.
- Inside this file, use relative paths for `outputDir` and `entryFile` (e.g., `./dist`, `src/main.ms`). This makes your project more portable, as it doesn't rely on absolute paths that might change between machines or users.
- Commit your main configuration file(s) to your version control system (like Git). This ensures everyone on the team (including your future self) uses the same build settings.

### Environment-Specific Configurations: Adapting to Different Terrains
For different deployment environments (like development, testing, production), you often need slightly different configurations (e.g., different API URLs, debug settings, output directories).
The `MS_CONFIG_FILE` environment variable is your best friend here.

```bash
# For your local development work
export MS_CONFIG_FILE=config/dev.yml
msc build

# When deploying to production (in your CI/CD script)
export MS_CONFIG_FILE=config/prod.yml
msc build
```

### Configuration Templates: Ready-Made Scrolls

Here's how those `dev.yml` and `prod.yml` might look:

**Development Settings** (`config/dev.yml`):
```yaml
compilerOptions:
  outputDir: ./build/dev # Keep development builds separate
  entryFile: src/main.ms
  # You might add debug flags or other dev-specific options here later
```

**Production Settings** (`config/prod.yml`):
```yaml
compilerOptions:
  outputDir: ./dist # Common directory for distributable/production files
  entryFile: src/main.ms
  # Production builds might have optimization flags enabled in the future
```
This way, your main build command (`msc build`) remains the same, and the environment variable subtly directs it to the correct set of instructions. Clever, eh?
