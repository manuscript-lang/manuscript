import {
    createConnection,
    TextDocuments,
    Diagnostic,
    DiagnosticSeverity,
    ProposedFeatures,
    InitializeParams,
    DidChangeConfigurationNotification,
    TextDocumentSyncKind,
    InitializeResult,
    TextDocumentPositionParams,
    CompletionItem,
    CompletionItemKind,
    HoverParams, // Added for Hover
    MarkupContent, // Added for Hover
    MarkupKind, // Added for Hover
    DocumentFormattingParams, // Added for Formatting
    TextEdit, // Added for Formatting
    FoldingRangeParams, // Added for Folding
    FoldingRange,       // Added for Folding
    FoldingRangeKind    // Added for Folding
} from 'vscode-languageserver/node';

import { TextDocument } from 'vscode-languageserver-textdocument';

// Create a connection for the server. The connection uses Node's IPC as a transport.
const connection = createConnection(ProposedFeatures.all);

const documents: TextDocuments<TextDocument> = new TextDocuments(TextDocument);

let hasConfigurationCapability = false;
let hasWorkspaceFolderCapability = false;
let hasDiagnosticRelatedInformationCapability = false; // Ensure it's declared

connection.onInitialize((params: InitializeParams) => {
    const capabilities = params.capabilities;
    hasConfigurationCapability = !!(capabilities.workspace && !!capabilities.workspace.configuration);
    hasWorkspaceFolderCapability = !!(capabilities.workspace && !!capabilities.workspace.workspaceFolders);
    hasDiagnosticRelatedInformationCapability = !!( // Initialize it here
        capabilities.textDocument &&
        capabilities.textDocument.publishDiagnostics &&
        capabilities.textDocument.publishDiagnostics.relatedInformation
    );

    const result: InitializeResult = {
        capabilities: {
            textDocumentSync: TextDocumentSyncKind.Incremental,
            completionProvider: {
                resolveProvider: true
            },
            hoverProvider: true, // Enable hover provider
            documentFormattingProvider: true, // Enable document formatting provider
            foldingRangeProvider: true // Enable folding range provider
            // definitionProvider: true // Future: Enable definition provider
        }
    };
    if (hasWorkspaceFolderCapability) {
        result.capabilities.workspace = {
            workspaceFolders: {
                supported: true
            }
        };
    }
    connection.console.log('Manuscript Language Server Initialized (with Hover, Formatting and Folding).');
    return result;
});

connection.onInitialized(() => {
    if (hasConfigurationCapability) {
        connection.client.register(DidChangeConfigurationNotification.type, undefined);
    }
    if (hasWorkspaceFolderCapability) {
        connection.workspace.onDidChangeWorkspaceFolders(_event => {
            connection.console.log('Workspace folder change event received.');
        });
    }
    connection.console.log('Manuscript Language Server ready (with Hover, Formatting and Folding).');
});

interface ManuscriptSettings {
    maxNumberOfProblems: number;
}
const defaultSettings: ManuscriptSettings = { maxNumberOfProblems: 1000 };
let globalSettings: ManuscriptSettings = defaultSettings;
const documentSettings: Map<string, Thenable<ManuscriptSettings>> = new Map();

connection.onDidChangeConfiguration(change => {
    if (hasConfigurationCapability) {
        documentSettings.clear();
    } else {
        globalSettings = <ManuscriptSettings>(
            (change.settings.manuscriptLanguageServer || defaultSettings)
        );
    }
    documents.all().forEach(validateTextDocument);
});

function getDocumentSettings(resource: string): Thenable<ManuscriptSettings> {
    if (!hasConfigurationCapability) {
        return Promise.resolve(globalSettings);
    }
    let result = documentSettings.get(resource);
    if (!result) {
        result = connection.workspace.getConfiguration({
            scopeUri: resource,
            section: 'manuscriptLanguageServer'
        });
        documentSettings.set(resource, result);
    }
    return result;
}

documents.onDidClose(e => {
    documentSettings.delete(e.document.uri);
});

documents.onDidChangeContent(change => {
    validateTextDocument(change.document);
});

async function validateTextDocument(textDocument: TextDocument): Promise<void> {
    connection.console.log(`Validating document: ${textDocument.uri}`);
    const settings = await getDocumentSettings(textDocument.uri); // Ensure settings are fetched
    const text = textDocument.getText();
    const diagnostics: Diagnostic[] = [];

    // ========================================================================
    // Placeholder for Manuscript-to-Go Transpilation and Go Diagnostics
    // ========================================================================
    connection.console.log('Attempting to transpile Manuscript to Go and get diagnostics...');

    try {
        // For now, let's add a dummy diagnostic to show it's working.
        // Remove this once actual diagnostics are implemented.
        if (text.length > 0) { // Only show if there's text
             const dummyLine = Math.min(textDocument.lineCount -1, 5); // Show on line 5 or last line
             const diagnostic: Diagnostic = {
                 severity: DiagnosticSeverity.Warning,
                 range: {
                     start: { line: dummyLine, character: 0 },
                     end: { line: dummyLine, character: textDocument.getText({start: {line: dummyLine, character: 0}, end: {line: dummyLine, character: Infinity}}).length }
                 },
                 message: 'Placeholder diagnostic. Transpilation & real linting not yet implemented.',
                 source: 'manuscript-lsp-stub'
             };
             if (hasDiagnosticRelatedInformationCapability) { // Check if capability exists
                diagnostic.relatedInformation = [
                    {
                        location: {
                            uri: textDocument.uri,
                            range: Object.assign({}, diagnostic.range)
                        },
                        message: 'This is a dummy related information for the placeholder diagnostic.'
                    }
                ];
            }
             diagnostics.push(diagnostic);
        }


    } catch (e) {
        connection.console.error(`Error during validation: ${e.stack || e.message || e}`);
        const diagnostic: Diagnostic = {
            severity: DiagnosticSeverity.Error,
            range: { // Default to start of document if error is not specific
                start: textDocument.positionAt(0),
                end: textDocument.positionAt(1)
            },
            message: `LSP Error: ${e.message}`,
            source: 'manuscript-lsp-error'
        };
        diagnostics.push(diagnostic);
    }
    // ========================================================================

    connection.sendDiagnostics({ uri: textDocument.uri, diagnostics });
    connection.console.log(`Diagnostics sent for ${textDocument.uri}`);
}

// Completion Provider
connection.onCompletion(
    (_textDocumentPosition: TextDocumentPositionParams): CompletionItem[] => {
        const keywords = [
            "let", "fn", "return", "yield", "type", "interface", "extends", "import", "export", "extern",
            "if", "else", "for", "while", "in", "match", "case", "default",
            "check", "try", "async", "await", "go", "defer",
            "as", "void", "null", "true", "false",
            "bool", "string", "number", "i8", "i16", "i32", "i64", "int", "uint8", "uint16", "uint32", "uint64", "f32", "f64", "long", "double"
        ];
        const keywordCompletions: CompletionItem[] = keywords.map(kw => ({
            label: kw,
            kind: CompletionItemKind.Keyword
        }));

        const snippetCompletions: CompletionItem[] = [
            {
                label: 'fn (function)',
                kind: CompletionItemKind.Snippet,
                insertText: 'fn ${1:name}(${2:params}) ${3:ReturnType} {\n\t${0}\n}',
                documentation: 'Define a function'
            },
            {
                label: 'let (variable)',
                kind: CompletionItemKind.Snippet,
                insertText: 'let ${1:name} = ${0:value};',
                documentation: 'Declare a variable'
            },
            {
                label: 'if',
                kind: CompletionItemKind.Snippet,
                insertText: 'if ${1:condition} {\n\t${0}\n}',
                documentation: 'If statement'
            },
            {
                label: 'if/else',
                kind: CompletionItemKind.Snippet,
                insertText: 'if ${1:condition} {\n\t${2}\n} else {\n\t${0}\n}',
                documentation: 'If/Else statement'
            },
            {
                label: 'for (loop)',
                kind: CompletionItemKind.Snippet,
                insertText: 'for ${1:item} in ${2:collection} {\n\t${0}\n}',
                documentation: 'For...in loop'
            },
            {
                label: 'type (struct)',
                kind: CompletionItemKind.Snippet,
                insertText: 'type ${1:Name} {\n\t${0}\n}',
                documentation: 'Define a new struct type'
            },
             {
                label: 'main (main function)',
                kind: CompletionItemKind.Snippet,
                insertText: 'fn main() {\n\t${0}\n}',
                documentation: 'Define the main entry point function'
            }
        ];
        return [...keywordCompletions, ...snippetCompletions];
    }
);

connection.onCompletionResolve(
    (item: CompletionItem): CompletionItem => {
        if (item.documentation) { 
            item.detail = String(item.documentation);
        } else if (item.kind === CompletionItemKind.Keyword) {
             item.detail = `Manuscript keyword: ${item.label}`;
        }
        return item;
    }
);

// Hover Provider
connection.onHover((params: HoverParams): import('vscode-languageserver').Hover | null => { // Ensure Hover is imported if this line is directly used
    const document = documents.get(params.textDocument.uri);
    if (!document) {
        return null;
    }
    const position = params.position;
    const offset = document.offsetAt(position);
    const text = document.getText();
    
    let start = offset;
    while (start > 0 && /\w/.test(text.charAt(start - 1))) {
        start--;
    }
    let end = offset;
    while (end < text.length && /\w/.test(text.charAt(end))) {
        end++;
    }
    const word = text.substring(start, end);

    if (!word) {
        return null;
    }

    let hoverContentValue = `*Manuscript LSP Hover (Placeholder)*

Token: \`${word}\`

Actual type information and documentation requires full semantic analysis or Go transpilation, which is not yet implemented.`;
    
    const keywordDocs: { [key: string]: string } = {
        "fn": "Declares a function. Functions are the basic units of executable code.",
        "let": "Declares a variable or constant. Use `let x = value;`.",
        "type": "Defines a new struct type (a collection of named fields).",
        "if": "Conditional execution based on a boolean expression.",
        "else": "Provides an alternative execution path for an `if` statement.",
        "for": "Looping construct. Typically used as `for item in collection`.",
        "return": "Exits a function, optionally returning a value.",
        "import": "Imports modules or symbols from other files/packages.",
        "export": "Makes symbols available for import from other modules.",
        "true": "Boolean literal representing truth.",
        "false": "Boolean literal representing falsehood.",
        "null": "Represents the absence of a value."
    };

    if (keywordDocs[word]) {
         hoverContentValue = `**${word}** (Manuscript Keyword)

${keywordDocs[word]}

*Further details will be available with full semantic analysis.*`;
    }

    const hoverContent: MarkupContent = {
        kind: MarkupKind.Markdown,
        value: hoverContentValue
    };

    return {
        contents: hoverContent,
    };
});


// Document Formatting Provider
connection.onDocumentFormatting(
    (params: DocumentFormattingParams): TextEdit[] => {
        const document = documents.get(params.textDocument.uri);
        if (!document) {
            return []; // No document found, no edits
        }

        // Placeholder: Show an information message and return no edits.
        connection.window.showInformationMessage(
            'Manuscript formatting is not yet implemented.'
        );
                
        return []; // Return no edits for now
    }
);

// Folding Range Provider
connection.onFoldingRanges((params: FoldingRangeParams): FoldingRange[] => {
    const document = documents.get(params.textDocument.uri);
    if (!document) {
        return [];
    }

    const ranges: FoldingRange[] = [];
    const lines = document.getText().split('\n'); // More robust to use document.lineAt if available for positions

    // Simple stack-based approach for brace folding
    const regionStack: { line: number; kind?: FoldingRangeKind }[] = [];

    // Regex for block comments and #region/#endregion
    const blockCommentStartRegex = /\/\*.*$/; // Matches start of block comment, rest on same line
    const blockCommentEndRegex = /^.*?\*\//;   // Matches end of block comment, rest on same line
    const regionStartRegex = /\/\s*#region\b/;
    const regionEndRegex = /\/\s*#endregion\b/;


    for (let i = 0; i < lines.length; i++) {
        const line = lines[i];

        // #region / #endregion folding
        if (regionStartRegex.test(line)) {
            regionStack.push({ line: i, kind: FoldingRangeKind.Region });
        } else if (regionEndRegex.test(line)) {
            const regionStart = regionStack.pop();
            if (regionStart && regionStart.kind === FoldingRangeKind.Region) {
                 // Ensure end line is not before start line
                if (i > regionStart.line) {
                    ranges.push(FoldingRange.create(regionStart.line, i, undefined, undefined, FoldingRangeKind.Region));
                }
            }
        }

        // Block comment folding /* ... */
        // This is a simplified version and might not handle nested block comments perfectly
        // or block comments that don't span the entire line initially.
        if (blockCommentStartRegex.test(line) && !line.match(blockCommentEndRegex)) { // Starts but doesn't end on same line
            let inBlockComment = true;
            let commentEndLine = i;
            for (let j = i + 1; j < lines.length; j++) {
                if (blockCommentEndRegex.test(lines[j])) {
                    commentEndLine = j;
                    inBlockComment = false;
                    break;
                }
            }
            if (!inBlockComment && commentEndLine > i) { // Found the end on a subsequent line
                 ranges.push(FoldingRange.create(i, commentEndLine, undefined, undefined, FoldingRangeKind.Comment));
                 i = commentEndLine; // Skip lines already processed as part of this comment block
                 continue;
            } else if (inBlockComment) { // Unclosed block comment till end of file
                 ranges.push(FoldingRange.create(i, lines.length -1, undefined, undefined, FoldingRangeKind.Comment));
                 break; // No more lines to process
            }
        }


        // Basic brace folding (very simple, improved version below)
        // Count open and close braces on the line
        const openBraces = (line.match(/\{/g) || []).length;
        const closeBraces = (line.match(/\}/g) || []).length;

        // Push open braces onto stack
        for (let j = 0; j < openBraces; j++) {
            // Try to find the column of the j-th '{'
            // let charIndex = -1;
            // for(let k=0; k<=j; k++) charIndex = line.indexOf('{', charIndex + 1);
            
            regionStack.push({ line: i });
        }

        // Pop for close braces and create ranges
        for (let j = 0; j < closeBraces; j++) {
            const regionStart = regionStack.pop();
            if (regionStart) {
                 // Ensure end line is not before start line
                if (i > regionStart.line) { // Multi-line block
                    ranges.push(FoldingRange.create(regionStart.line, i));
                } else { // Single-line block, check character positions if possible
                    // This simple version doesn't store char for start, so single line {} might not be ideal
                    // A more robust solution would store start character too.
                    // For now, we only add if it's a multi-line block.
                }
            }
        }
    }
    
    // A more robust indentation-based folding could be added here too,
    // or the brace-based one could be improved to be more accurate with columns.

    return ranges;
});


documents.listen(connection);
connection.listen();
connection.console.log('Manuscript Language Server process started (with hover, snippets, formatting placeholder, and folding).');
