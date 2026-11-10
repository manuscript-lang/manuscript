// expect-stdout: close 3
// expect-stdout: close 2
// expect-stdout: close 1
// expect-stdout: close 6
// expect-stdout: close 5
// expect-stdout: close 4
// expect-stdout: close 10
// expect-stdout: close 9
// expect-stdout: close 8
// expect-stdout: close 7
// expect-stdout: close 13
// expect-stdout: close 12
// expect-stdout: close 11
// Destructuring closes omitted resource fields even when their types own no heap storage.
// Omitted fields close last declared first, before the fields moved into named bindings.
import Closeable from "@std/core.ms"
import stdout from "@std/io/io.ms"

type Token:
    id: Int

impl Closeable for Token:
    var fn close() Unit!:
        return stdout().write("close {self.id}\n")

type Triple:
    first: Token
    second: Token
    third: Token

type Nested:
    kept: Token
    omitted: Triple

type NamedToken:
    id: Int
    name: String

impl Closeable for NamedToken:
    var fn close() Unit!:
        return stdout().write("close {self.id}\n")

type NamedTriple:
    first: NamedToken
    second: NamedToken
    third: NamedToken

fn local() Unit:
    tokens := Triple(Token(1), Token(2), Token(3))
    {first: kept} := tokens
    _ := kept.id

fn temporary() Unit:
    {first: kept} := Triple(Token(4), Token(5), Token(6))
    _ := kept.id

fn nested() Unit:
    tokens := Nested(Token(7), Triple(Token(8), Token(9), Token(10)))
    {kept: kept} := tokens
    _ := kept.id

fn with_storage() Unit:
    tokens := NamedTriple(
        NamedToken(11, "first-heap-allocated-name"),
        NamedToken(12, "second-heap-allocated-name"),
        NamedToken(13, "third-heap-allocated-name")
    )
    {first: kept} := tokens
    _ := kept.name.length()

export fn main() Int:
    local()
    temporary()
    nested()
    with_storage()
    return 0
