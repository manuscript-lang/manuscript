---
title: "Examples"
linkTitle: "Examples"

description: >
  Practical code examples demonstrating Manuscript features and best practices.
---

This section contains practical examples demonstrating how to use Manuscript effectively. All examples are tested and ready to run.

## Quick Examples

### Hello World
```ms
fn main() {
  print("Hello, Manuscript!")
}
```

### Variables and Types
```ms
fn main() {
  let name = "Alice"
  let age = 30
  let score = 95.5
  let active = true
  
  print("User: ${name}, Age: ${age}, Score: ${score}, Active: ${active}")
}
```

### Functions
```ms
fn greet(name string, enthusiastic bool = false) string {
  let punctuation = enthusiastic ? "!" : "."
  return "Hello, ${name}${punctuation}"
}

fn main() {
  print(greet("World"))
  print(greet("Manuscript", true))
}
```

### Error Handling
```ms
fn divide(a float, b float) float! {
  if b == 0.0 {
    return error("Division by zero")
  }
  return a / b
}

fn main() {
  let result = try divide(10.0, 2.0)
  print("Result: ${result}")
  
  let safe = try divide(10.0, 0.0) else 0.0
  print("Safe result: ${safe}")
}
```

## Example Categories

### [Basic Examples](basic/)
Fundamental language features and common patterns:

- **Variables and Types** - Working with different data types
- **Functions** - Function definition and usage patterns
- **Control Flow** - Conditions, loops, and branching
- **Collections** - Arrays, objects, maps, and sets
- **String Processing** - Text manipulation and formatting

### [Applications](applications/)
Complete, real-world applications:

- **CLI Tools** - Command-line utilities and scripts
- **Web Services** - HTTP servers and API endpoints
- **Data Processing** - File parsing and data transformation
- **Utilities** - Helper functions and common algorithms

## Featured Examples

### Configuration Parser
A practical example that parses configuration files:

```ms
import { readFile } from 'os'
import { split, trim } from 'strings'

type Config {
  host string
  port int
  debug bool
  features []string
}

fn parseConfig(filename string) Config! {
  let content = try readFile(filename)
  let config = Config{
    host: "localhost"
    port: 8080
    debug: false
    features: []
  }
  
  let lines = split(content, "\n")
  for line in lines {
    let cleaned = trim(line)
    if cleaned == "" || startsWith(cleaned, "#") {
      continue  // Skip empty lines and comments
    }
    
    let parts = split(cleaned, "=")
    if len(parts) != 2 {
      continue  // Skip malformed lines
    }
    
    let key = trim(parts[0])
    let value = trim(parts[1])
    
    match key {
      "host": config.host = value
      "port": config.port = parseInt(value)
      "debug": config.debug = value == "true"
      "features": config.features = split(value, ",")
    }
  }
  
  return config
}

fn main() {
  let config = try parseConfig("app.conf") else {
    print("Error loading config: ${error}")
    return
  }
  
  print("Server: ${config.host}:${config.port}")
  print("Debug: ${config.debug}")
  print("Features: ${join(config.features, ", ")}")
}
```

### Simple HTTP Server
Basic web server demonstrating Manuscript's web capabilities:

```ms
import { http } from 'net'
import { json } from 'encoding'

type User {
  id int
  name string
  email string
}

let users = []User{
  User{id: 1, name: "Alice", email: "alice@example.com"}
  User{id: 2, name: "Bob", email: "bob@example.com"}
}

fn handleUsers(req http.Request) http.Response! {
  match req.method {
    "GET": {
      let body = try json.marshal(users)
      return http.Response{
        status: 200
        headers: {"Content-Type": "application/json"}
        body: body
      }
    }
    "POST": {
      let user = try json.unmarshal(req.body, User)
      user.id = len(users) + 1
      users.append(user)
      
      let body = try json.marshal(user)
      return http.Response{
        status: 201
        headers: {"Content-Type": "application/json"}
        body: body
      }
    }
    default: {
      return http.Response{
        status: 405
        body: "Method not allowed"
      }
    }
  }
}

fn main() {
  let server = http.Server{port: 8080}
  
  server.handle("/users", handleUsers)
  server.handle("/health", fn(req) {
    return http.Response{status: 200, body: "OK"}
  })
  
  print("Server starting on port 8080...")
  try server.listen()
}
```

### Data Processing Pipeline
Example showing data transformation and processing:

```ms
import { readFile, writeFile } from 'os'
import { split, trim, join } from 'strings'
import { parseFloat } from 'strconv'

type Sale {
  date string
  product string
  amount float
  customer string
}

fn parseSalesData(content string) []Sale! {
  let lines = split(content, "\n")
  let sales = []Sale
  
  for i, line in lines {
    if i == 0 || trim(line) == "" {
      continue  // Skip header and empty lines
    }
    
    let fields = split(line, ",")
    if len(fields) != 4 {
      return error("Invalid format at line ${i + 1}")
    }
    
    let amount = try parseFloat(trim(fields[2]))
    
    sales.append(Sale{
      date: trim(fields[0])
      product: trim(fields[1])
      amount: amount
      customer: trim(fields[3])
    })
  }
  
  return sales
}

fn generateReport(sales []Sale) string {
  let totalSales = 0.0
  let productTotals = [:]float
  let customerTotals = [:]float
  
  for sale in sales {
    totalSales += sale.amount
    productTotals[sale.product] = productTotals[sale.product] + sale.amount
    customerTotals[sale.customer] = customerTotals[sale.customer] + sale.amount
  }
  
  let report = []string{
    "Sales Report"
    "============"
    ""
    "Total Sales: $${totalSales}"
    "Number of Transactions: ${len(sales)}"
    "Average Sale: $${totalSales / float(len(sales))}"
    ""
    "Top Products:"
  }
  
  // Add top products (simplified)
  for product, total in productTotals {
    report.append("  ${product}: $${total}")
  }
  
  return join(report, "\n")
}

fn main() {
  let content = try readFile("sales.csv") else {
    print("Error reading file: ${error}")
    return
  }
  
  let sales = try parseSalesData(content) else {
    print("Error parsing data: ${error}")
    return
  }
  
  let report = generateReport(sales)
  
  try writeFile("report.txt", report) else {
    print("Error writing report: ${error}")
    return
  }
  
  print("Report generated successfully!")
  print("Processed ${len(sales)} sales records")
}
```

## How to Use These Examples

### Running Examples

1. **Copy the code** into a `.ms` file
2. **Install dependencies** if needed (imports)
3. **Compile and run**:
   ```bash
   msc example.ms
   ```

### Modifying Examples

- **Change parameters** to see different behavior
- **Add error handling** for edge cases
- **Extend functionality** with new features
- **Combine examples** to build larger applications

### Example Data

Many examples require test data. Create sample files:

```bash
# For configuration example
echo "host=api.example.com
port=3000
debug=true
features=auth,logging,metrics" > app.conf

# For sales data example
echo "Date,Product,Amount,Customer
2024-01-01,Widget A,29.99,John Doe
2024-01-02,Widget B,45.50,Jane Smith
2024-01-03,Widget A,29.99,Bob Johnson" > sales.csv
```

## Learning Path

1. **Start with Basic Examples** - Understand fundamental concepts
2. **Study Applications** - See how concepts combine
3. **Modify Examples** - Experiment with variations
4. **Build Your Own** - Create original applications
5. **Share Back** - Contribute your examples

## Contributing Examples

We welcome example contributions! Good examples:

- **Solve real problems** - Address common use cases
- **Are well-documented** - Include clear explanations
- **Follow best practices** - Demonstrate good Manuscript style
- **Include test data** - Provide sample inputs when needed

See our [Contributing Guide](https://github.com/manuscript-co/manuscript/blob/main/CONTRIBUTING.md) for details.

{{% alert title="Interactive Learning" %}}
The best way to learn is by doing! Copy these examples, run them, modify them, and see what happens.
{{% /alert %}} 