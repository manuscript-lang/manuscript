// expect-stdout: close 3
// expect-stdout: close 2
// expect-stdout: close 1
// expect-stdout: code 7
// expect-stdout: close 6
// expect-stdout: close 5
// expect-stdout: close 4
// expect-stdout: code 8
// expect-stdout: close 8
// expect-stdout: kept 7 9
// expect-stdout: close 9
// expect-stdout: close 7
// expect-stdout: borrowed 10 9
// expect-stdout: close 12
// expect-stdout: close 11
// expect-stdout: close 10
// expect-stdout: close 15
// expect-stdout: close 14
// expect-stdout: close 13
// expect-stdout: wildcard 0
// expect-stdout: close 17
// expect-stdout: close 16
// expect-stdout: generic 11
// expect-stdout: empty 0
// A match that moves named fields closes omitted resource payloads last declared first,
// including resources with no heap storage. Borrowed matches keep the owner's close duty.
import Closeable from "@std/core.ms"

type Token:
	id: Int

impl Closeable for Token:
	var fn close() Unit!:
		print("close {self.id}")

type NamedToken:
	id: Int
	name: String

impl Closeable for NamedToken:
	var fn close() Unit!:
		print("close {self.id}")

enum Choice:
	Full(first: Token, second: Token, third: Token, code: Int)
	Empty

enum NamedChoice:
	NamedFull(first: NamedToken, second: NamedToken, third: NamedToken, code: Int)
	NamedEmpty

enum GenericChoice[T]:
	GenericFull(first: T, second: T, code: Int)
	GenericEmpty

fn scalar_omitted() Unit:
	value := Full(Token(1), Token(2), Token(3), 7)

	code := match value:
		Full(_, _, _, code): code
		Empty: 0

	print("code {code}")

fn heap_omitted() Unit:
	value := NamedFull(
		NamedToken(4, "first"), NamedToken(5, "second"), NamedToken(6, "third"), 8
	)

	code := match value:
		NamedFull(_, _, _, code): code
		NamedEmpty: 0

	print("code {code}")

fn mixed() Unit:
	value := Full(Token(7), Token(8), Token(9), 0)

	_ := match value:
		Full(first, _, third, _):
			print("kept {first.id} {third.id}")
		Empty: unit

fn borrowed() Unit:
	value := Full(Token(10), Token(11), Token(12), 9)

	code := match value:
		Full(first, _, _, code): code + first.id
		Empty: 0

	original := match value:
		Full(_, _, _, saved): saved
		Empty: 0

	print("borrowed {code - original} {original}")

	_ := match value:
		Full(first, _, _, _): first.id
		Empty: 0

fn wildcard() Unit:
	value := Full(Token(13), Token(14), Token(15), 0)

	code := match value:
		_: 0

	print("wildcard {code}")

fn generic() Unit:
	value := GenericFull(Token(16), Token(17), 11)

	code := match value:
		GenericFull(_, _, code): code
		GenericEmpty: 0

	print("generic {code}")

fn empty() Unit:
	value: Choice := Empty

	code := match value:
		Full(_, _, _, code): code
		Empty: 0

	print("empty {code}")

fn main() Unit:
	scalar_omitted()
	heap_omitted()
	mixed()
	borrowed()
	wildcard()
	generic()
	empty()
