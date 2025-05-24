---
title: "Building a CLI Tool"
linkTitle: "CLI Tool"
weight: 1
description: >
  Learn to build a complete command-line tool with Manuscript, covering argument parsing, file operations, and error handling.
---

In this tutorial, we'll build a complete command-line tool that processes text files. You'll learn how to handle command-line arguments, read files, process data, and handle errors gracefully.

## What We'll Build

A text analysis tool called `wordcount` that:
- Counts words, lines, and characters in text files
- Supports multiple files
- Provides different output formats
- Handles errors gracefully

## Project Setup

Create a new directory for our project:

```bash
mkdir wordcount-tool
cd wordcount-tool
```

## Step 1: Basic Structure

Let's start with a simple main function:

```ms
// main.ms
fn main() {
  print("WordCount Tool v1.0")
  print("Usage: wordcount <file1> [file2] [file3]...")
}
```

Test it:
```bash
msc main.ms
```

## Step 2: Command Line Arguments

Manuscript provides access to command-line arguments through the `args` built-in:

```ms
// main.ms
fn main() {
  let arguments = args()
  
  if len(arguments) < 2 {
    print("Usage: wordcount <file1> [file2] [file3]...")
    return
  }
  
  // Skip the program name (first argument)
  let files = arguments[1:]
  
  print("Processing ${len(files)} file(s):")
  for file in files {
    print("  - ${file}")
  }
}
```

## Step 3: File Reading

Let's add file reading capability:

```ms
// main.ms
import { readFile } from 'os'

fn processFile(filename string) {
  print("Processing: ${filename}")
  
  let content = try readFile(filename) else {
    print("Error: Could not read file '${filename}'")
    return
  }
  
  print("File read successfully!")
  print("Content length: ${len(content)} characters")
}

fn main() {
  let arguments = args()
  
  if len(arguments) < 2 {
    print("Usage: wordcount <file1> [file2] [file3]...")
    return
  }
  
  let files = arguments[1:]
  
  for file in files {
    processFile(file)
    print("")  // Empty line between files
  }
}
```

## Step 4: Text Analysis

Now let's implement the actual word counting:

```ms
// main.ms
import { readFile } from 'os'
import { split, trim } from 'strings'

type FileStats {
  filename string
  lines int
  words int
  characters int
}

fn analyzeText(content string) (int, int, int) {
  let characters = len(content)
  
  // Count lines
  let lines = len(split(content, "\n"))
  
  // Count words
  let words = 0
  let wordList = split(trim(content), " ")
  for word in wordList {
    if trim(word) != "" {
      words += 1
    }
  }
  
  return lines, words, characters
}

fn processFile(filename string) FileStats! {
  let content = try readFile(filename)
  let lines, words, characters = analyzeText(content)
  
  return FileStats{
    filename: filename
    lines: lines
    words: words
    characters: characters
  }
}

fn printStats(stats FileStats) {
  print("File: ${stats.filename}")
  print("  Lines: ${stats.lines}")
  print("  Words: ${stats.words}")
  print("  Characters: ${stats.characters}")
}

fn main() {
  let arguments = args()
  
  if len(arguments) < 2 {
    print("Usage: wordcount <file1> [file2] [file3]...")
    return
  }
  
  let files = arguments[1:]
  let allStats = []FileStats
  
  for file in files {
    let stats = try processFile(file) else {
      print("Error processing '${file}': ${error}")
      continue
    }
    
    allStats.append(stats)
    printStats(stats)
    print("")
  }
  
  // Print summary if multiple files
  if len(allStats) > 1 {
    printSummary(allStats)
  }
}
```

## Step 5: Summary Statistics

Add a summary for multiple files:

```ms
fn printSummary(statsList []FileStats) {
  let totalLines = 0
  let totalWords = 0
  let totalChars = 0
  
  for stats in statsList {
    totalLines += stats.lines
    totalWords += stats.words
    totalChars += stats.characters
  }
  
  print("=== SUMMARY ===")
  print("Total files: ${len(statsList)}")
  print("Total lines: ${totalLines}")
  print("Total words: ${totalWords}")
  print("Total characters: ${totalChars}")
  print("Average words per file: ${totalWords / len(statsList)}")
}
```

## Step 6: Command Line Options

Let's add support for command-line flags:

```ms
// Add this to the top of main.ms
type Config {
  verbose bool
  format string  // "table", "json", "csv"
  showSummary bool
}

fn parseArguments(args []string) (Config, []string) {
  let config = Config{
    verbose: false
    format: "table"
    showSummary: true
  }
  let files = []string
  
  for i = 1; i < len(args); i++ {
    let arg = args[i]
    
    match arg {
      "--verbose", "-v": {
        config.verbose = true
      }
      "--format": {
        if i + 1 < len(args) {
          config.format = args[i + 1]
          i += 1  // Skip next argument
        }
      }
      "--no-summary": {
        config.showSummary = false
      }
      default: {
        if !startsWith(arg, "-") {
          files.append(arg)
        } else {
          print("Unknown option: ${arg}")
        }
      }
    }
  }
  
  return config, files
}

fn main() {
  let arguments = args()
  
  if len(arguments) < 2 {
    printUsage()
    return
  }
  
  let config, files = parseArguments(arguments)
  
  if len(files) == 0 {
    print("Error: No files specified")
    printUsage()
    return
  }
  
  let allStats = []FileStats
  
  for file in files {
    if config.verbose {
      print("Processing: ${file}")
    }
    
    let stats = try processFile(file) else {
      print("Error processing '${file}': ${error}")
      continue
    }
    
    allStats.append(stats)
  }
  
  // Output results in requested format
  outputResults(allStats, config)
}

fn printUsage() {
  print("WordCount Tool v1.0")
  print("Usage: wordcount [options] <file1> [file2] [file3]...")
  print("")
  print("Options:")
  print("  -v, --verbose     Verbose output")
  print("  --format FORMAT   Output format (table, json, csv)")
  print("  --no-summary      Don't show summary for multiple files")
}
```

## Step 7: Output Formats

Add different output formats:

```ms
fn outputResults(statsList []FileStats, config Config) {
  match config.format {
    "json": outputJSON(statsList)
    "csv": outputCSV(statsList)
    "table": outputTable(statsList)
    default: {
      print("Unknown format: ${config.format}")
      outputTable(statsList)
    }
  }
  
  if config.showSummary && len(statsList) > 1 {
    print("")
    printSummary(statsList)
  }
}

fn outputTable(statsList []FileStats) {
  print("File                    Lines    Words    Characters")
  print("=" * 50)
  
  for stats in statsList {
    let filename = stats.filename
    if len(filename) > 20 {
      filename = filename[:17] + "..."
    }
    
    print("${filename.padRight(20)} ${stats.lines.toString().padLeft(8)} ${stats.words.toString().padLeft(8)} ${stats.characters.toString().padLeft(12)}")
  }
}

fn outputJSON(statsList []FileStats) {
  print("{")
  print("  \"files\": [")
  
  for i, stats in statsList {
    print("    {")
    print("      \"filename\": \"${stats.filename}\",")
    print("      \"lines\": ${stats.lines},")
    print("      \"words\": ${stats.words},")
    print("      \"characters\": ${stats.characters}")
    
    if i < len(statsList) - 1 {
      print("    },")
    } else {
      print("    }")
    }
  }
  
  print("  ]")
  print("}")
}

fn outputCSV(statsList []FileStats) {
  print("filename,lines,words,characters")
  
  for stats in statsList {
    print("${stats.filename},${stats.lines},${stats.words},${stats.characters}")
  }
}
```

## Step 8: Testing Our Tool

Create some test files:

```bash
# Create test files
echo "Hello world
This is a test file
with multiple lines" > test1.txt

echo "Short file" > test2.txt

echo "Lorem ipsum dolor sit amet
consectetur adipiscing elit
sed do eiusmod tempor incididunt" > test3.txt
```

Test the tool:

```bash
# Basic usage
msc main.ms test1.txt

# Multiple files
msc main.ms test1.txt test2.txt test3.txt

# With options
msc main.ms --verbose --format json test1.txt test2.txt

# CSV format
msc main.ms --format csv test*.txt

# No summary
msc main.ms --no-summary test1.txt test2.txt
```

## Step 9: Error Handling Improvements

Add better error handling:

```ms
fn processFile(filename string) FileStats! {
  // Check if file exists
  if !fileExists(filename) {
    return error("File does not exist: ${filename}")
  }
  
  // Try to read the file
  let content = try readFile(filename) else {
    return error("Permission denied or file is not readable: ${filename}")
  }
  
  let lines, words, characters = analyzeText(content)
  
  return FileStats{
    filename: filename
    lines: lines
    words: words
    characters: characters
  }
}

fn analyzeText(content string) (int, int, int) {
  let characters = len(content)
  
  // Handle empty files
  if characters == 0 {
    return 0, 0, 0
  }
  
  // Count lines (handle different line endings)
  let lines = len(split(content, "\n"))
  if !endsWith(content, "\n") && characters > 0 {
    // File doesn't end with newline, but has content
    lines = max(1, lines)
  }
  
  // Count words more accurately
  let words = 0
  let inWord = false
  
  for char in content {
    if isWhitespace(char) {
      inWord = false
    } else if !inWord {
      words += 1
      inWord = true
    }
  }
  
  return lines, words, characters
}
```

## Step 10: Building and Distribution

Build the final tool:

```bash
# Build the tool
msc -o wordcount main.ms

# Make it executable
chmod +x wordcount

# Test the built version
./wordcount --help
./wordcount test1.txt test2.txt
```

## Complete Code

Here's the complete `main.ms` file:

```ms
import { readFile, fileExists } from 'os'
import { split, trim, startsWith, endsWith } from 'strings'

type FileStats {
  filename string
  lines int
  words int
  characters int
}

type Config {
  verbose bool
  format string
  showSummary bool
}

fn main() {
  let arguments = args()
  
  if len(arguments) < 2 {
    printUsage()
    return
  }
  
  let config, files = parseArguments(arguments)
  
  if len(files) == 0 {
    print("Error: No files specified")
    printUsage()
    return
  }
  
  let allStats = []FileStats
  
  for file in files {
    if config.verbose {
      print("Processing: ${file}")
    }
    
    let stats = try processFile(file) else {
      print("Error: ${error}")
      continue
    }
    
    allStats.append(stats)
  }
  
  if len(allStats) == 0 {
    print("Error: No files could be processed")
    return
  }
  
  outputResults(allStats, config)
}

// ... (include all the other functions from above)
```

## What You've Learned

In this tutorial, you've learned:

1. **Project structure** - Organizing a Manuscript project
2. **Command-line arguments** - Parsing args and flags
3. **File operations** - Reading files safely
4. **Error handling** - Using `try`/`else` and bang functions
5. **Data structures** - Custom types and collections
6. **String processing** - Text analysis and formatting
7. **Pattern matching** - Using `match` for options
8. **Code organization** - Breaking code into functions

## Next Steps

Enhance the tool further:

1. **Add more statistics** - Most common words, average word length
2. **Support directories** - Recursively process all text files
3. **Add filtering** - Include/exclude files by pattern
4. **Performance optimization** - Handle very large files
5. **Configuration files** - Support config files for default options
6. **Testing** - Add unit tests for your functions

## Resources

- [Error Handling Guide](../../intermediate/error-handling/)
- [Type System Guide](../../intermediate/type-system/)
- [Standard Library Reference](../../reference/standard-library/)

{{% alert title="Pro Tip" %}}
CLI tools are a great way to learn a new language because they cover many fundamental concepts: I/O, string processing, error handling, and program structure.
{{% /alert %}} 