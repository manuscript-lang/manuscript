package transpiler

import (
	"fmt"
	"go/ast"
	"go/token"

	mast "manuscript-lang/manuscript/internal/ast"
)

// VisitCodeBlock transpiles code blocks to Go block statements
func (t *GoTranspiler) VisitCodeBlock(node *mast.CodeBlock) ast.Node {
	if node == nil {
		return &ast.BlockStmt{List: []ast.Stmt{}}
	}

	var stmts []ast.Stmt

	for _, stmt := range node.Stmts {
		if stmt == nil {
			continue
		}

		result := t.Visit(stmt)
		if result == nil {
			continue
		}

		switch goStmt := result.(type) {
		case *PipelineBlockStmt:
			// Preserve pipeline blocks as-is by adding the underlying BlockStmt
			stmts = append(stmts, goStmt.BlockStmt)
		case *DestructuringBlockStmt:
			// Preserve destructuring blocks as-is by adding the underlying BlockStmt
			stmts = append(stmts, goStmt.BlockStmt)
		case *ast.BlockStmt:
			// Flatten other block statements into the parent block
			stmts = append(stmts, goStmt.List...)
		case ast.Stmt:
			stmts = append(stmts, goStmt)
		case ast.Expr:
			// Convert expression to expression statement
			stmts = append(stmts, &ast.ExprStmt{X: goStmt})
		default:
			// Handle other types
			if expr, ok := result.(ast.Expr); ok {
				stmts = append(stmts, &ast.ExprStmt{X: expr})
			}
		}
	}

	return &ast.BlockStmt{List: stmts}
}

// VisitLoopBody transpiles loop bodies to Go block statements
func (t *GoTranspiler) VisitLoopBody(node *mast.LoopBody) ast.Node {
	if node == nil {
		return &ast.BlockStmt{List: []ast.Stmt{}}
	}

	var stmts []ast.Stmt

	for _, stmt := range node.Stmts {
		if stmt == nil {
			continue
		}

		result := t.Visit(stmt)
		if result == nil {
			continue
		}

		switch goStmt := result.(type) {
		case ast.Stmt:
			stmts = append(stmts, goStmt)
		case ast.Expr:
			// Convert expression to expression statement
			stmts = append(stmts, &ast.ExprStmt{X: goStmt})
		default:
			// Handle other types
			if expr, ok := result.(ast.Expr); ok {
				stmts = append(stmts, &ast.ExprStmt{X: expr})
			}
		}
	}

	return &ast.BlockStmt{List: stmts}
}

// VisitExprStmt transpiles expression statements
func (t *GoTranspiler) VisitExprStmt(node *mast.ExprStmt) ast.Node {
	if node == nil || node.Expr == nil {
		return nil
	}

	result := t.Visit(node.Expr)

	// If the expression generated a statement (like an assignment), return it directly
	if goStmt, ok := result.(ast.Stmt); ok {
		return goStmt
	}

	// Otherwise, wrap the expression in an expression statement
	if goExpr, ok := result.(ast.Expr); ok {
		return &ast.ExprStmt{X: goExpr}
	}

	return nil
}

// VisitReturnStmt transpiles return statements
func (t *GoTranspiler) VisitReturnStmt(node *mast.ReturnStmt) ast.Node {
	if node == nil {
		return &ast.ReturnStmt{Return: t.pos(node)}
	}

	var results []ast.Expr

	for _, value := range node.Values {
		if value == nil {
			continue
		}

		result := t.Visit(value)
		if goExpr, ok := result.(ast.Expr); ok {
			results = append(results, goExpr)
		}
	}

	returnStmt := &ast.ReturnStmt{
		Return:  t.pos(node),
		Results: results,
	}

	t.registerNodeMapping(returnStmt, node)
	return returnStmt
}

// VisitYieldStmt transpiles yield statements to generator pattern using channels
func (t *GoTranspiler) VisitYieldStmt(node *mast.YieldStmt) ast.Node {
	var yieldArg ast.Expr = &ast.Ident{Name: "nil"}

	if node != nil && len(node.Values) > 0 {
		var results []ast.Expr
		for _, value := range node.Values {
			if value == nil {
				continue
			}
			if result := t.Visit(value); result != nil {
				if goExpr, ok := result.(ast.Expr); ok {
					results = append(results, goExpr)
				}
			}
		}

		switch len(results) {
		case 0:
			// yieldArg already set to nil
		case 1:
			yieldArg = results[0]
		default:
			yieldArg = &ast.CompositeLit{
				Type: &ast.ArrayType{
					Elt: &ast.InterfaceType{Methods: &ast.FieldList{}},
				},
				Elts: results,
			}
		}
	}

	return &ast.ExprStmt{
		X: &ast.CallExpr{
			Fun:  &ast.Ident{Name: "__yield"},
			Args: []ast.Expr{yieldArg},
		},
	}
}

// VisitDeferStmt transpiles defer statements
func (t *GoTranspiler) VisitDeferStmt(node *mast.DeferStmt) ast.Node {
	if node == nil || node.Expr == nil {
		return nil
	}

	stmt := t.Visit(node.Expr)
	if goExpr, ok := stmt.(ast.Expr); ok {
		// In Go, defer only works with function calls
		if callExpr, ok := goExpr.(*ast.CallExpr); ok {
			return &ast.DeferStmt{Call: callExpr}
		} else {
			// Convert other expressions to function calls if possible
			if ident, ok := goExpr.(*ast.Ident); ok {
				return &ast.DeferStmt{
					Call: &ast.CallExpr{
						Fun:  ident,
						Args: []ast.Expr{},
					},
				}
			}
		}
	}

	return nil
}

// VisitAsyncStmt transpiles async statements to Go's go statement
func (t *GoTranspiler) VisitAsyncStmt(node *mast.AsyncStmt) ast.Node {
	return t.transpileAsyncGoStmt(node.Expr)
}

// VisitGoStmt transpiles go statements to Go's go statement
func (t *GoTranspiler) VisitGoStmt(node *mast.GoStmt) ast.Node {
	return t.transpileAsyncGoStmt(node.Expr)
}

// transpileAsyncGoStmt is a shared helper for transpiling both async and go statements
func (t *GoTranspiler) transpileAsyncGoStmt(expr mast.Expression) ast.Node {
	if expr == nil {
		return nil
	}

	stmt := t.Visit(expr)
	if goExpr, ok := stmt.(ast.Expr); ok {
		// In Go, go only works with function calls
		if callExpr, ok := goExpr.(*ast.CallExpr); ok {
			return &ast.GoStmt{Call: callExpr}
		}
		// Generate error for non-function-call expressions
		t.addError("async/go statements can only be used with function calls", expr)
		return nil
	}

	return nil
}

// VisitBreakStmt transpiles break statements
func (t *GoTranspiler) VisitBreakStmt(node *mast.BreakStmt) ast.Node {
	return t.createBranchStmt(node, token.BREAK, "break statement outside of loop")
}

// VisitContinueStmt transpiles continue statements
func (t *GoTranspiler) VisitContinueStmt(node *mast.ContinueStmt) ast.Node {
	return t.createBranchStmt(node, token.CONTINUE, "continue statement outside of loop")
}

// createBranchStmt creates a branch statement (break/continue) with loop validation
func (t *GoTranspiler) createBranchStmt(node mast.Node, tok token.Token, errorMsg string) ast.Node {
	if !t.isInLoop() {
		t.addError(errorMsg, node)
		return nil
	}

	branchStmt := &ast.BranchStmt{
		TokPos: t.pos(node),
		Tok:    tok,
	}

	t.registerNodeMapping(branchStmt, node)
	return branchStmt
}

// VisitCheckStmt transpiles check statements (error checking)
func (t *GoTranspiler) VisitCheckStmt(node *mast.CheckStmt) ast.Node {
	if node == nil || node.Expr == nil {
		t.addError("invalid check statement", node)
		return nil
	}

	// Add errors import if not already present
	t.addErrorsImport()

	// Convert check to if statement that returns error
	condition := t.Visit(node.Expr)
	if condExpr, ok := condition.(ast.Expr); ok {
		// Create: if !condition { return nil, errors.New("error message") }
		notCondition := &ast.UnaryExpr{
			Op: token.NOT,
			X:  condExpr,
		}

		message := node.Message
		if message == "" {
			message = "check failed"
		}

		// Create errors.New("message") call
		errorsNewCall := &ast.CallExpr{
			Fun: &ast.SelectorExpr{
				X:   &ast.Ident{Name: "errors"},
				Sel: &ast.Ident{Name: "New"},
			},
			Args: []ast.Expr{
				&ast.BasicLit{
					Kind:  token.STRING,
					Value: `"` + message + `"`,
				},
			},
		}

		// Create return statement: return nil, errors.New("message")
		returnStmt := &ast.ReturnStmt{
			Results: []ast.Expr{
				&ast.Ident{Name: "nil"},
				errorsNewCall,
			},
		}

		return &ast.IfStmt{
			Cond: notCondition,
			Body: &ast.BlockStmt{
				List: []ast.Stmt{returnStmt},
			},
		}
	}

	return nil
}

// VisitTryStmt transpiles try statements
func (t *GoTranspiler) VisitTryStmt(node *mast.TryStmt) ast.Node {
	if node == nil || node.Expr == nil {
		t.addError("invalid try statement", node)
		return nil
	}

	// Get the expression to try
	expr := t.Visit(node.Expr)
	goExpr, ok := expr.(ast.Expr)
	if !ok {
		t.addError("try expression is not a valid expression", node)
		return &ast.BlockStmt{List: []ast.Stmt{}}
	}

	// Generate error handling pattern:
	// _, err := expr()
	// if err != nil {
	//     return nil, err
	// }

	errIdent := &ast.Ident{Name: "err"}
	underscoreIdent := &ast.Ident{Name: "_"}

	// Assignment: _, err := expr()
	assignStmt := &ast.AssignStmt{
		Lhs: []ast.Expr{underscoreIdent, errIdent},
		Tok: token.DEFINE,
		Rhs: []ast.Expr{goExpr},
	}

	// Error check: if err != nil { return nil, err }
	ifStmt := &ast.IfStmt{
		Cond: &ast.BinaryExpr{
			X:  errIdent,
			Op: token.NEQ,
			Y:  &ast.Ident{Name: "nil"},
		},
		Body: &ast.BlockStmt{
			List: []ast.Stmt{
				&ast.ReturnStmt{
					Results: []ast.Expr{
						&ast.Ident{Name: "nil"},
						errIdent,
					},
				},
			},
		},
	}

	return &ast.BlockStmt{List: []ast.Stmt{assignStmt, ifStmt}}
}

// VisitIfStmt transpiles if statements
func (t *GoTranspiler) VisitIfStmt(node *mast.IfStmt) ast.Node {
	if node == nil || node.Cond == nil {
		t.addError("invalid if statement", node)
		return nil
	}

	condition := t.Visit(node.Cond)
	condExpr, ok := condition.(ast.Expr)
	if !ok {
		t.addError("if condition is not a valid expression", node)
		return nil
	}

	// Build then block
	var thenBlock *ast.BlockStmt
	if node.Then != nil {
		thenResult := t.Visit(node.Then)
		if block, ok := thenResult.(*ast.BlockStmt); ok {
			thenBlock = block
		} else {
			thenBlock = &ast.BlockStmt{List: []ast.Stmt{}}
		}
	} else {
		thenBlock = &ast.BlockStmt{List: []ast.Stmt{}}
	}

	// Build else block if present
	var elseStmt ast.Stmt
	if node.Else != nil {
		elseResult := t.Visit(node.Else)
		if block, ok := elseResult.(*ast.BlockStmt); ok {
			elseStmt = block
		} else if stmt, ok := elseResult.(ast.Stmt); ok {
			elseStmt = stmt
		}
	}

	ifStmt := &ast.IfStmt{
		If:   t.pos(node),
		Cond: condExpr,
		Body: thenBlock,
		Else: elseStmt,
	}

	t.registerNodeMapping(ifStmt, node)
	return ifStmt
}

// VisitForStmt transpiles for statements
func (t *GoTranspiler) VisitForStmt(node *mast.ForStmt) ast.Node {
	if node == nil {
		t.addError("invalid for statement", node)
		return nil
	}

	t.enterLoop()
	defer t.exitLoop()

	// Visit the loop to get the specific type
	if node.Loop != nil {
		loopResult := t.Visit(node.Loop)
		if rangeStmt, ok := loopResult.(*ast.RangeStmt); ok {
			rangeStmt.For = t.pos(node)
			return rangeStmt
		} else if forStmt, ok := loopResult.(*ast.ForStmt); ok {
			forStmt.For = t.pos(node)
			return forStmt
		}
	}

	// Default: infinite loop
	forStmt := &ast.ForStmt{
		For:  t.pos(node),
		Body: &ast.BlockStmt{List: []ast.Stmt{}},
	}

	t.registerNodeMapping(forStmt, node)
	return forStmt
}

// VisitWhileStmt transpiles while statements
func (t *GoTranspiler) VisitWhileStmt(node *mast.WhileStmt) ast.Node {
	if node == nil {
		t.addError("invalid while statement", node)
		return nil
	}

	t.enterLoop()
	defer t.exitLoop()

	var condition ast.Expr
	if node.Cond != nil {
		condResult := t.Visit(node.Cond)
		if condExpr, ok := condResult.(ast.Expr); ok {
			condition = condExpr
		}
	}

	var body *ast.BlockStmt
	if node.Body != nil {
		bodyResult := t.Visit(node.Body)
		if block, ok := bodyResult.(*ast.BlockStmt); ok {
			body = block
		} else {
			body = &ast.BlockStmt{List: []ast.Stmt{}}
		}
	} else {
		body = &ast.BlockStmt{List: []ast.Stmt{}}
	}

	return &ast.ForStmt{
		For:  t.pos(node),
		Cond: condition,
		Body: body,
	}
}

// VisitPipedStmt transpiles piped statements to the proper pipeline loop structure
func (t *GoTranspiler) VisitPipedStmt(node *mast.PipedStmt) ast.Node {
	if node == nil || len(node.Calls) < 2 {
		t.addError("invalid piped statement - need at least source and one target", node)
		return nil
	}

	var stmts []ast.Stmt

	// First call is the source, rest are pipeline targets
	sourceCall := &node.Calls[0]
	targetCalls := node.Calls[1:]

	// Create processor variables for each pipeline target
	for i, call := range targetCalls {
		procVarName := fmt.Sprintf("proc%d", i+1)

		// Get the function expression
		var funcExpr ast.Expr
		if call.Expr != nil {
			exprResult := t.Visit(call.Expr)
			if expr, ok := exprResult.(ast.Expr); ok {
				funcExpr = expr
			} else {
				funcExpr = &ast.Ident{Name: "nil"}
			}
		} else {
			funcExpr = &ast.Ident{Name: "nil"}
		}

		// Build arguments from this specific call's Args
		var args []ast.Expr
		for j := range call.Args {
			arg := &call.Args[j]
			argResult := t.Visit(arg.Value)
			if argExpr, ok := argResult.(ast.Expr); ok {
				args = append(args, argExpr)
			}
		}

		// Create the processor assignment: procN := func(args...)
		var procRhs ast.Expr

		// Check if the function expression is already a call (like obj.method())
		if callExpr, isCall := funcExpr.(*ast.CallExpr); isCall {
			// If it's already a call and has args, append our pipeline args
			if len(args) > 0 {
				callExpr.Args = append(callExpr.Args, args...)
			}
			procRhs = callExpr
		} else if len(args) > 0 {
			// The target has pipeline arguments, so we need to create a function call with those args
			procRhs = &ast.CallExpr{
				Fun:  funcExpr,
				Args: args,
			}
		} else {
			// No pipeline arguments, and target is not a function call
			// Different handling based on expression type:
			switch funcExpr.(type) {
			case *ast.IndexExpr:
				// Array access (arr[0]) - use as processor directly, do NOT add ()
				procRhs = funcExpr
			case *ast.SelectorExpr:
				// Method call (obj.method) - use as processor directly (no parentheses)
				procRhs = funcExpr
			default:
				// Identifier or other - wrap in function call
				procRhs = &ast.CallExpr{
					Fun:  funcExpr,
					Args: []ast.Expr{},
				}
			}
		}

		procAssign := &ast.AssignStmt{
			Lhs: []ast.Expr{&ast.Ident{Name: procVarName}},
			Tok: token.DEFINE,
			Rhs: []ast.Expr{procRhs},
		}
		stmts = append(stmts, procAssign)
	}

	// Get the source expression for the range loop
	var sourceExpr ast.Expr
	if sourceCall.Expr != nil {
		sourceResult := t.Visit(sourceCall.Expr)
		if expr, ok := sourceResult.(ast.Expr); ok {
			// Check if it's already a function call, if not make it one
			if _, isCall := expr.(*ast.CallExpr); !isCall {
				sourceExpr = &ast.CallExpr{
					Fun:  expr,
					Args: []ast.Expr{},
				}
			} else {
				sourceExpr = expr
			}
		} else {
			sourceExpr = &ast.Ident{Name: "nil"}
		}
	} else {
		sourceExpr = &ast.Ident{Name: "nil"}
	}

	// Handle source arguments if any
	if len(sourceCall.Args) > 0 {
		var sourceArgs []ast.Expr
		for j := range sourceCall.Args {
			arg := &sourceCall.Args[j]
			argResult := t.Visit(arg.Value)
			if argExpr, ok := argResult.(ast.Expr); ok {
				sourceArgs = append(sourceArgs, argExpr)
			}
		}

		// Add arguments to the source call
		if callExpr, isCall := sourceExpr.(*ast.CallExpr); isCall {
			callExpr.Args = append(callExpr.Args, sourceArgs...)
		}
	}

	// Build the pipeline loop body
	var loopStmts []ast.Stmt

	// Create pipeline variables: a1 := v, a2 := proc1(a1), etc.
	for i := 0; i < len(targetCalls)+1; i++ {
		varName := fmt.Sprintf("a%d", i+1)

		var rhs ast.Expr
		if i == 0 {
			// First assignment: a1 := v
			rhs = &ast.Ident{Name: "v"}
		} else {
			// Subsequent assignments: aN := procN-1(aN-1)
			procName := fmt.Sprintf("proc%d", i)
			prevVarName := fmt.Sprintf("a%d", i)

			rhs = &ast.CallExpr{
				Fun:  &ast.Ident{Name: procName},
				Args: []ast.Expr{&ast.Ident{Name: prevVarName}},
			}
		}

		assignment := &ast.AssignStmt{
			Lhs: []ast.Expr{&ast.Ident{Name: varName}},
			Tok: token.DEFINE,
			Rhs: []ast.Expr{rhs},
		}
		loopStmts = append(loopStmts, assignment)
	}

	// Create the range loop: for _, v := range source() { ... }
	rangeLoop := &ast.RangeStmt{
		Key:   &ast.Ident{Name: "_"},
		Value: &ast.Ident{Name: "v"},
		Tok:   token.DEFINE,
		X:     sourceExpr,
		Body:  &ast.BlockStmt{List: loopStmts},
	}
	stmts = append(stmts, rangeLoop)

	// Return a PipelineBlockStmt containing the pipeline statements
	// This dedicated type will be preserved by the VisitCodeBlock flattening logic
	return &PipelineBlockStmt{
		BlockStmt: &ast.BlockStmt{List: stmts},
	}
}

// VisitPipedCall transpiles piped call expressions
func (t *GoTranspiler) VisitPipedCall(node *mast.PipedCall) ast.Node {
	if node == nil {
		return nil
	}

	// Get the base expression (function to call)
	var funcExpr ast.Expr
	if node.Expr != nil {
		exprResult := t.Visit(node.Expr)
		if expr, ok := exprResult.(ast.Expr); ok {
			funcExpr = expr
		} else {
			funcExpr = &ast.Ident{Name: "nil"}
		}
	} else {
		funcExpr = &ast.Ident{Name: "nil"}
	}

	// Build arguments from piped args
	var args []ast.Expr
	for i := range node.Args {
		arg := &node.Args[i]
		argResult := t.Visit(arg)
		if argExpr, ok := argResult.(ast.Expr); ok {
			args = append(args, argExpr)
		}
	}

	return &ast.CallExpr{
		Fun:  funcExpr,
		Args: args,
	}
}

// VisitPipedArg transpiles piped arguments
func (t *GoTranspiler) VisitPipedArg(node *mast.PipedArg) ast.Node {
	if node == nil || node.Value == nil {
		return nil
	}

	// For piped arguments, we typically just want the value expression
	return t.Visit(node.Value)
}
