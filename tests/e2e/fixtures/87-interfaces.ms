// @test: Interfaces - interface keyword, embedding, structural satisfaction

// === Interface: method signatures only ===
interface Serializable
  fn serialize(): string
  fn deserialize(data: string)

// === Concrete type satisfies interface implicitly ===
type JsonDoc
  data: string
  fn serialize(): string
    data
  fn deserialize(s: string)
    data = s

fn process(s: Serializable): string
  s.serialize()

let doc = JsonDoc(data: "x")
// @expect: x
print(process(doc))

// === Interface embedding ===
interface Reader
  fn read(): string

interface Writer
  fn write(data: string): void

interface ReadWriter
  Reader
  Writer
  fn read(): string

type Buffer
  content: string = ""
  fn read(): string
    content
  fn write(data: string): void
    content = content + data

fn useReadWriter(rw: ReadWriter): string
  rw.write("x")
  rw.read()

let buf = Buffer()
// @expect: x
print(useReadWriter(buf))
