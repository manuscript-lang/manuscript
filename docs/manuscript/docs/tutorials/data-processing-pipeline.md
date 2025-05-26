---
title: "Data Processing Pipeline"
linkTitle: "Data Processing Pipeline"
weight: 30
description: >
  Build a data transformation tool showcasing Manuscript's piped syntax and functional programming patterns.
---

# Data Processing Pipeline Tutorial

In this tutorial, you'll build a complete data processing pipeline using Manuscript's powerful piped syntax. You'll learn how to transform, filter, and analyze data in a clean, readable way that's perfect for data processing workflows.

## What You'll Build

A log analysis tool that processes web server logs to generate insights about traffic patterns, popular pages, and error rates. The tool will demonstrate:

- Reading and parsing log files
- Using piped syntax for data transformation
- Filtering and aggregating data
- Generating formatted reports

## What You'll Learn

- How to use Manuscript's piped syntax effectively
- Data transformation patterns
- File I/O operations
- Error handling in data pipelines
- Performance considerations for data processing

## Prerequisites

- [Getting Started](../getting-started/) - Basic Manuscript setup
- [Functions](../features/functions/) - Understanding function definitions
- [Variables](../features/variables/) - Variable declarations and types
- [Piped Syntax](../features/piped-syntax/) - Pipeline fundamentals

## Project Setup

Create a new directory for your project:

```bash
mkdir log-analyzer
cd log-analyzer
```

Create the main file:

```bash
touch main.ms
```

## Step 1: Define Data Structures

First, let's define the data structures we'll work with:

```ms
// main.ms
import { readFile, writeFile } from 'os'
import { split, trim, contains } from 'strings'
import { parseTime, formatTime } from 'time'

type LogEntry {
  timestamp string
  method string
  path string
  status int
  size int
  userAgent string
  ip string
}

type PageStats {
  path string
  hits int
  totalSize int
  avgSize float
}

type Report {
  totalRequests int
  uniquePages int
  errorRate float
  topPages []PageStats
  hourlyStats [:]int
}
```

## Step 2: Basic Parsing Functions

Create functions to parse individual log entries:

```ms
fn parseLogLine(line string) LogEntry! {
  // Parse Apache Common Log Format
  // Example: 127.0.0.1 - - [10/Oct/2000:13:55:36 -0700] "GET /apache_pb.gif HTTP/1.0" 200 2326
  
  if trim(line) == "" {
    return error("Empty line")
  }
  
  // Simplified parsing - in real code you'd use regex
  let parts = split(line, " ")
  if len(parts) < 10 {
    return error("Invalid log format")
  }
  
  let ip = parts[0]
  let timestamp = parts[3] + " " + parts[4] // [timestamp]
  let method = trim(parts[5], "\"")
  let path = parts[6]
  let status = parseInt(parts[8])
  let size = parseInt(parts[9])
  let userAgent = if len(parts) > 11 { parts[11] } else { "" }
  
  return LogEntry{
    ip: ip
    timestamp: timestamp
    method: method
    path: path
    status: status
    size: size
    userAgent: userAgent
  }
}

fn isValidEntry(entry LogEntry) bool {
  return entry.status > 0 && entry.path != ""
}

fn isErrorStatus(entry LogEntry) bool {
  return entry.status >= 400
}

fn isSuccessStatus(entry LogEntry) bool {
  return entry.status >= 200 && entry.status < 300
}
```

## Step 3: Data Processing with Traditional Approach

Let's first implement the traditional imperative approach:

```ms
fn analyzeLogsTraditional(filename string) Report! {
  let content = try readFile(filename)
  let lines = split(content, "\n")
  
  let entries = []LogEntry
  let parseErrors = 0
  
  // Parse all lines
  for line in lines {
    let entry = try parseLogLine(line) else {
      parseErrors++
      continue
    }
    
    if isValidEntry(entry) {
      entries.append(entry)
    }
  }
  
  // Calculate statistics
  let totalRequests = len(entries)
  let errorCount = 0
  let pageHits = [:]int
  let pageSizes = [:]int
  let hourlyStats = [:]int
  
  for entry in entries {
    if isErrorStatus(entry) {
      errorCount++
    }
    
    pageHits[entry.path] = pageHits[entry.path] + 1
    pageSizes[entry.path] = pageSizes[entry.path] + entry.size
    
    let hour = extractHour(entry.timestamp)
    hourlyStats[hour] = hourlyStats[hour] + 1
  }
  
  // Generate top pages
  let topPages = []PageStats
  for path, hits in pageHits {
    let totalSize = pageSizes[path]
    let avgSize = float(totalSize) / float(hits)
    
    topPages.append(PageStats{
      path: path
      hits: hits
      totalSize: totalSize
      avgSize: avgSize
    })
  }
  
  // Sort by hits (simplified)
  sortPagesByHits(topPages)
  
  return Report{
    totalRequests: totalRequests
    uniquePages: len(pageHits)
    errorRate: float(errorCount) / float(totalRequests)
    topPages: topPages[0:min(10, len(topPages))]
    hourlyStats: hourlyStats
  }
}
```

## Step 4: Data Processing with Piped Syntax

Now let's implement the same logic using Manuscript's piped syntax for a cleaner, more readable approach:

```ms
fn parseLines(content string) []string {
  return split(content, "\n")
}

fn parseEntries(lines []string) []LogEntry {
  let entries = []LogEntry
  for line in lines {
    let entry = try parseLogLine(line) else { continue }
    if isValidEntry(entry) {
      entries.append(entry)
    }
  }
  return entries
}

fn calculatePageStats(entries []LogEntry) []PageStats {
  let pageHits = [:]int
  let pageSizes = [:]int
  
  for entry in entries {
    pageHits[entry.path] = pageHits[entry.path] + 1
    pageSizes[entry.path] = pageSizes[entry.path] + entry.size
  }
  
  let stats = []PageStats
  for path, hits in pageHits {
    let totalSize = pageSizes[path]
    stats.append(PageStats{
      path: path
      hits: hits
      totalSize: totalSize
      avgSize: float(totalSize) / float(hits)
    })
  }
  
  return stats
}

fn sortByHits(stats []PageStats) []PageStats {
  // Sort by hits descending (simplified implementation)
  return sortPagesByHits(stats)
}

fn takeTop(stats []PageStats, count int) []PageStats {
  return stats[0:min(count, len(stats))]
}

fn calculateErrorRate(entries []LogEntry) float {
  let errorCount = 0
  for entry in entries {
    if isErrorStatus(entry) {
      errorCount++
    }
  }
  return float(errorCount) / float(len(entries))
}

fn calculateHourlyStats(entries []LogEntry) [:]int {
  let hourlyStats = [:]int
  for entry in entries {
    let hour = extractHour(entry.timestamp)
    hourlyStats[hour] = hourlyStats[hour] + 1
  }
  return hourlyStats
}

fn buildReport(entries []LogEntry, topPages []PageStats, errorRate float, hourlyStats [:]int) Report {
  return Report{
    totalRequests: len(entries)
    uniquePages: len(topPages)
    errorRate: errorRate
    topPages: topPages
    hourlyStats: hourlyStats
  }
}

fn analyzeLogsPiped(filename string) Report! {
  let entries = readFile(filename) 
    | parseLines 
    | parseEntries
  
  let topPages = entries 
    | calculatePageStats 
    | sortByHits 
    | takeTop count=10
  
  let errorRate = entries | calculateErrorRate
  let hourlyStats = entries | calculateHourlyStats
  
  return buildReport(entries, topPages, errorRate, hourlyStats)
}
```

## Step 5: Advanced Pipeline Patterns

Let's explore more advanced pipeline patterns:

```ms
// Filtering pipelines
fn analyzeSuccessfulRequests(filename string) []LogEntry! {
  return readFile(filename)
    | parseLines
    | parseEntries
    | filterSuccessful
}

fn filterSuccessful(entries []LogEntry) []LogEntry {
  let filtered = []LogEntry
  for entry in entries {
    if isSuccessStatus(entry) {
      filtered.append(entry)
    }
  }
  return filtered
}

// Transformation pipelines
fn extractPopularPaths(filename string) []string! {
  return readFile(filename)
    | parseLines
    | parseEntries
    | calculatePageStats
    | sortByHits
    | takeTop count=5
    | extractPaths
}

fn extractPaths(stats []PageStats) []string {
  let paths = []string
  for stat in stats {
    paths.append(stat.path)
  }
  return paths
}

// Aggregation pipelines
fn generateHourlyReport(filename string) string! {
  let hourlyStats = readFile(filename)
    | parseLines
    | parseEntries
    | calculateHourlyStats
  
  return hourlyStats | formatHourlyReport
}

fn formatHourlyReport(stats [:]int) string {
  let report = []string{"Hourly Traffic Report", "===================", ""}
  
  for hour, count in stats {
    report.append("${hour}:00 - ${count} requests")
  }
  
  return join(report, "\n")
}
```

## Step 6: Error Handling in Pipelines

Manuscript's error handling works seamlessly with piped syntax:

```ms
fn safeAnalyzeLog(filename string) Report! {
  // Using try with pipelines
  let entries = try readFile(filename) 
    | parseLines 
    | parseEntries
  
  if len(entries) == 0 {
    return error("No valid log entries found")
  }
  
  let topPages = try entries 
    | calculatePageStats 
    | sortByHits 
    | takeTop count=10
  
  let errorRate = entries | calculateErrorRate
  let hourlyStats = entries | calculateHourlyStats
  
  return buildReport(entries, topPages, errorRate, hourlyStats)
}

// Alternative: Handle errors at each stage
fn robustAnalyzeLog(filename string) Report! {
  let content = try readFile(filename) else {
    return error("Failed to read file: ${error}")
  }
  
  let lines = content | parseLines
  if len(lines) == 0 {
    return error("File is empty")
  }
  
  let entries = lines | parseEntries
  if len(entries) == 0 {
    return error("No valid log entries found")
  }
  
  // Continue with pipeline processing...
  let topPages = entries 
    | calculatePageStats 
    | sortByHits 
    | takeTop count=10
  
  let errorRate = entries | calculateErrorRate
  let hourlyStats = entries | calculateHourlyStats
  
  return buildReport(entries, topPages, errorRate, hourlyStats)
}
```

## Step 7: Complete Application

Here's the complete application with a main function:

```ms
fn formatReport(report Report) string {
  let output = []string{
    "Log Analysis Report"
    "==================="
    ""
    "Total Requests: ${report.totalRequests}"
    "Unique Pages: ${report.uniquePages}"
    "Error Rate: ${report.errorRate * 100:.2f}%"
    ""
    "Top Pages:"
  }
  
  for i, page in report.topPages {
    output.append("${i+1}. ${page.path} (${page.hits} hits, avg ${page.avgSize:.0f} bytes)")
  }
  
  output.append("")
  output.append("Hourly Distribution:")
  for hour, count in report.hourlyStats {
    output.append("${hour}:00 - ${count} requests")
  }
  
  return join(output, "\n")
}

fn main() {
  let args = getArgs()
  if len(args) < 2 {
    print("Usage: log-analyzer <logfile>")
    return
  }
  
  let filename = args[1]
  
  // Process using piped syntax
  let report = try analyzeLogsPiped(filename) else {
    print("Error analyzing log: ${error}")
    return
  }
  
  // Generate and save report
  let reportText = report | formatReport
  
  try writeFile("analysis-report.txt", reportText) else {
    print("Error writing report: ${error}")
    return
  }
  
  print("Analysis complete! Report saved to analysis-report.txt")
  print("Processed ${report.totalRequests} requests from ${report.uniquePages} unique pages")
}

// Helper functions
fn extractHour(timestamp string) string {
  // Extract hour from timestamp - simplified implementation
  return "12" // Placeholder
}

fn sortPagesByHits(stats []PageStats) []PageStats {
  // Sort implementation - simplified
  return stats
}

fn min(a int, b int) int {
  return if a < b { a } else { b }
}

fn parseInt(s string) int {
  // Parse integer - simplified
  return 0
}

fn getArgs() []string {
  // Get command line arguments - simplified
  return ["log-analyzer", "access.log"]
}

fn join(parts []string, sep string) string {
  // Join strings - simplified
  return ""
}
```

## Step 8: Testing Your Pipeline

Create a sample log file to test with:

```bash
# Create sample log data
cat > access.log << 'EOF'
127.0.0.1 - - [10/Oct/2000:13:55:36 -0700] "GET /index.html HTTP/1.0" 200 1234
127.0.0.1 - - [10/Oct/2000:13:56:02 -0700] "GET /about.html HTTP/1.0" 200 2345
127.0.0.1 - - [10/Oct/2000:13:56:15 -0700] "GET /contact.html HTTP/1.0" 404 567
192.168.1.1 - - [10/Oct/2000:14:01:22 -0700] "POST /api/users HTTP/1.0" 201 890
192.168.1.1 - - [10/Oct/2000:14:02:33 -0700] "GET /index.html HTTP/1.0" 200 1234
EOF
```

Run your analyzer:

```bash
msc main.ms
./main access.log
```

## Key Takeaways

### Benefits of Piped Syntax

1. **Readability** - Data flow is clear and left-to-right
2. **Composability** - Easy to add, remove, or reorder processing steps
3. **Testability** - Each function can be tested independently
4. **Reusability** - Functions can be used in different pipeline combinations

### When to Use Pipelines

- **Data transformation workflows** - Perfect for ETL operations
- **Sequential processing** - When each step depends on the previous
- **Functional programming** - When you want to avoid mutable state
- **Stream processing** - For handling large datasets efficiently

### Performance Considerations

- Pipelines create intermediate collections between stages
- For very large datasets, consider streaming approaches
- Profile your code to identify bottlenecks
- Consider parallel processing for independent operations

## Next Steps

- [Error Handling](../features/error-handling/) - Advanced error patterns
- [Performance Optimization](../advanced/performance/) - Optimizing data processing
- [Testing](../best-practices/testing/) - Testing pipeline components
- [Modules](../features/modules/) - Organizing pipeline code

## Complete Source Code

The complete source code for this tutorial is available in our [examples repository](https://github.com/manuscript-lang/examples/tree/main/data-processing-pipeline).

{{% alert title="Practice Exercise" %}}
Try extending the log analyzer to:
1. Parse different log formats (JSON, CSV)
2. Add real-time processing capabilities
3. Generate charts and visualizations
4. Add configuration file support
{{% /alert %}} 