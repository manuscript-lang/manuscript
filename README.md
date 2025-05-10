# manuscript
Programming language for AI engineering

## Prerequisites

- Go 1.22 or later
- Java (required only for regenerating parser from grammar)

## Setup
For convenience, the generated parser files will be committed to the repository, so you can build and run the application without Java:

```
go mod tidy
make 
./build/msc
```

### Generating Parser from Grammar (Java Required)
If you want to modify the grammar and regenerate the parser:

1. Install Java if not already installed
2. Generate the parser from the grammar:
   ```
   make generate_parser
   ```
3. Build the application:
   ```
   make build
   ```
4. Run the application:
   ```
   ./build/msc
   ```
