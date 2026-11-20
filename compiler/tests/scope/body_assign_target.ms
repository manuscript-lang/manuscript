// Assignment to a name that is no binding: a declaration, or nothing.
LIMIT := 3

fn helper() Int:
	return 1

fn assign_constant() Int:
	LIMIT = 4
	return 0

fn assign_function() Int:
	helper = 2
	return 0

fn assign_missing() Int:
	missing = 5
	return 0
