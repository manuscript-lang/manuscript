// PostgreSQL frontend/backend protocol v3: message encoding and decoding, in pure
// Manuscript.
import Bytes, BytesBuilder from "@std/bytes.ms"

// Backend message types.
export AUTHENTICATION: UInt8 := 82
export PARAMETER_STATUS: UInt8 := 83
export BACKEND_KEY: UInt8 := 75
export READY_FOR_QUERY: UInt8 := 90
export ROW_DESCRIPTION: UInt8 := 84
export DATA_ROW: UInt8 := 68
export COMMAND_COMPLETE: UInt8 := 67
export ERROR_RESPONSE: UInt8 := 69
export NOTICE_RESPONSE: UInt8 := 78
export NOTIFICATION: UInt8 := 65
export NEGOTIATE_VERSION: UInt8 := 118
export PARSE_COMPLETE: UInt8 := 49
export BIND_COMPLETE: UInt8 := 50
export CLOSE_COMPLETE: UInt8 := 51
export NO_DATA: UInt8 := 110
export PARAMETER_DESCRIPTION: UInt8 := 116
export EMPTY_QUERY: UInt8 := 73
export PORTAL_SUSPENDED: UInt8 := 115
// Frontend message types.
QUERY: UInt8 := 81
PARSE: UInt8 := 80
BIND: UInt8 := 66
DESCRIBE: UInt8 := 68
EXECUTE: UInt8 := 69
CLOSE: UInt8 := 67
SYNC: UInt8 := 83
TERMINATE: UInt8 := 88
PASSWORD: UInt8 := 112
// What `describe` and `close` name.
export STATEMENT: UInt8 := 83
export PORTAL: UInt8 := 80
// The transaction status byte of ReadyForQuery.
export STATUS_IDLE: UInt8 := 73
export STATUS_IN_TRANSACTION: UInt8 := 84
export STATUS_FAILED: UInt8 := 69

// One column of a row description.
export type Field:
	name: String
	type_oid: Int
	format: Int

// One backend message, decoded from a frame.
export enum Backend:
	AuthOk
	AuthCleartext
	AuthMd5(salt: Bytes)
	AuthSasl(mechanisms: List[String])
	AuthSaslContinue(data: Bytes)
	AuthSaslFinal(data: Bytes)
	ParameterStatus(name: String, value: String)
	BackendKeyData(pid: Int, secret: Int)
	ReadyForQuery(status: UInt8)
	RowDescription(fields: List[Field])
	DataRow(columns: List[Bytes?])
	CommandComplete(tag: String)
	ErrorResponse(fields: Map[String, String])
	NoticeResponse(fields: Map[String, String])
	ParseComplete
	BindComplete
	CloseComplete
	NoData
	ParameterDescription(oids: List[Int])
	EmptyQuery
	PortalSuspended
	// Asynchronous or negotiation messages this client does not act on.
	Ignored

fn too_large() Error:
	return Error("postgres: message too large", kind: "EMSGSIZE")

fn size32(count: Int) Int32!:
	return count.to_int32().ok_or(too_large())

fn count16(count: Int) Int16!:
	return count.to_int16().ok_or(too_large())

fn framed(code: UInt8, body: Bytes) Bytes!:
	var out = BytesBuilder()
	out.append(code)
	out.append_int32_be(size32(body.length() + 4)?)
	out.append_bytes(body)
	return ok(out.build())

fn cstring(var out: BytesBuilder, text: String) Unit:
	out.append_bytes(text.to_bytes())
	out.append(0)

// The startup message, sent first; it has no type byte.
export fn startup(user: String, database: String, options: Map[String, String]) Bytes!:
	var body = BytesBuilder()
	body.append_int32_be(196608)
	cstring(var body, "user")
	cstring(var body, user)
	cstring(var body, "database")
	cstring(var body, database)

	for entry in options:
		cstring(var body, entry.key)
		cstring(var body, entry.value)

	body.append(0)

	payload := body.build()
	var out = BytesBuilder()
	out.append_int32_be(size32(payload.length() + 4)?)
	out.append_bytes(payload)
	return ok(out.build())

// Asks the server to switch to TLS.
export fn ssl_request() Bytes:
	var out = BytesBuilder()
	out.append_int32_be(8)
	out.append_int32_be(80877103)
	return out.build()

export fn terminate() Bytes!:
	return framed(TERMINATE, Bytes([]))

export fn sync() Bytes!:
	return framed(SYNC, Bytes([]))

export fn query(sql: String) Bytes!:
	var body = BytesBuilder()
	cstring(var body, sql)
	return framed(QUERY, body.build())

export fn password(text: String) Bytes!:
	var body = BytesBuilder()
	cstring(var body, text)
	return framed(PASSWORD, body.build())

// SASLInitialResponse: mechanism name and the client-first message.
export fn sasl_initial(mechanism: String, first: Bytes) Bytes!:
	var body = BytesBuilder()
	cstring(var body, mechanism)
	body.append_int32_be(size32(first.length())?)
	body.append_bytes(first)
	return framed(PASSWORD, body.build())

export fn sasl_response(data: Bytes) Bytes!:
	return framed(PASSWORD, data)

export fn parse(name: String, sql: String, oids: List[Int]) Bytes!:
	var body = BytesBuilder()
	cstring(var body, name)
	cstring(var body, sql)
	body.append_int16_be(count16(oids.length())?)
	for oid in oids: body.append_int32_be(size32(oid)?)
	return framed(PARSE, body.build())

// Bind with text-format parameters (none means NULL) and binary or text results.
export fn bind(
	portal: String,
	name: String,
	params: List[Bytes?],
	result_binary: Bool,
) Bytes!:
	var body = BytesBuilder()
	cstring(var body, portal)
	cstring(var body, name)
	body.append_int16_be(0)
	body.append_int16_be(count16(params.length())?)

	for param in params:
		if value := param:
			body.append_int32_be(size32(value.length())?)
			body.append_bytes(value)
		else:
			body.append_int32_be(-1)

	body.append_int16_be(1)
	body.append_int16_be(if result_binary: 1 else: 0)
	return framed(BIND, body.build())

// Describes a statement (`STATEMENT`) or a portal (`PORTAL`).
export fn describe(kind: UInt8, name: String) Bytes!:
	var body = BytesBuilder()
	body.append(kind)
	cstring(var body, name)
	return framed(DESCRIBE, body.build())

export fn close_statement(name: String) Bytes!:
	var body = BytesBuilder()
	body.append(STATEMENT)
	cstring(var body, name)
	return framed(CLOSE, body.build())

export fn execute(portal: String, max_rows: Int) Bytes!:
	var body = BytesBuilder()
	cstring(var body, portal)
	body.append_int32_be(size32(max_rows)?)
	return framed(EXECUTE, body.build())

// Big-endian integer reads that return Int.
export fn u16(data: Bytes, at: Int) Int!:
	return ok((data.uint16_be(at)?).to_int())

export fn u32(data: Bytes, at: Int) Int!:
	return ok((data.uint32_be(at)?).to_int())

export fn i32(data: Bytes, at: Int) Int!:
	return ok((data.int32_be(at)?).to_int())

type CString:
	text: String
	next: Int

fn bad(what: String) Error:
	return Error("postgres: malformed {what}", kind: "EBADMSG")

fn read_cstring(data: Bytes, at: Int) CString!:
	end := data.index_of_byte(0, at).ok_or(bad("string"))?
	text := data.decode_utf8_range(at, end).ok_or(bad("text"))?
	return ok(CString(text, end + 1))

fn fields_of(data: Bytes) Map[String, String]!:
	var out = Map[String, String]()
	var at = 0

	while at < data.length():
		code := data.get(at)
		if code == 0: break

		entry := read_cstring(data, at + 1)?
		key := Bytes([code]).decode_utf8().ok_or(bad("field"))?
		out.add(key, entry.text.clone())
		at = entry.next

	return ok(out)

fn row_description(data: Bytes) Backend!:
	count := u16(data, 0)?
	var at = 2
	var fields = List[Field]()

	for _i in 0..count:
		name := read_cstring(data, at)?
		at = name.next
		fields.append(Field(name.text.clone(), u32(data, at + 6)?, u16(data, at + 16)?))
		at += 18

	return ok(Backend.RowDescription(fields))

fn data_row(data: Bytes) Backend!:
	count := u16(data, 0)?
	var at = 2
	var columns = List[Bytes?]()

	for _i in 0..count:
		size := i32(data, at)?
		at += 4

		if size < 0:
			columns.append(none)
		else:
			columns.append(data.slice(at, at + size)?)
			at += size

	return ok(Backend.DataRow(columns))

fn authentication(data: Bytes) Backend!:
	kind := i32(data, 0)?
	rest := data.slice(4, data.length())?
	if kind == 0: return ok(Backend.AuthOk)
	if kind == 3: return ok(Backend.AuthCleartext)
	if kind == 5: return ok(Backend.AuthMd5(rest))
	if kind == 11: return ok(Backend.AuthSaslContinue(rest))
	if kind == 12: return ok(Backend.AuthSaslFinal(rest))
	if kind != 10: return error(
		Error(
			"postgres: unsupported authentication method {kind}",
			kind: "ENOTSUP",
		)
	)

	var names = List[String]()
	var at = 4

	while at < data.length() and data.get(at) != 0:
		entry := read_cstring(data, at)?
		names.append(entry.text.clone())
		at = entry.next

	return ok(Backend.AuthSasl(names))

// Decodes the body of one backend message with type byte `code`. An unknown type is an
// error.
export fn decode_message(code: UInt8, data: Bytes) Backend!:
	if code == AUTHENTICATION: return authentication(data)

	if code == PARAMETER_STATUS:
		name := read_cstring(data, 0)?
		value := read_cstring(data, name.next)?
		return ok(Backend.ParameterStatus(name.text.clone(), value.text.clone()))

	if code == BACKEND_KEY: return ok(
		Backend.BackendKeyData(i32(data, 0)?, i32(data, 4)?)
	)
	if code == READY_FOR_QUERY: return ok(Backend.ReadyForQuery(data.uint8(0)?))
	if code == ROW_DESCRIPTION: return row_description(data)
	if code == DATA_ROW: return data_row(data)

	if code == COMMAND_COMPLETE:
		tag := read_cstring(data, 0)?
		return ok(Backend.CommandComplete(tag.text.clone()))

	if code == ERROR_RESPONSE: return ok(Backend.ErrorResponse(fields_of(data)?))
	if code == NOTICE_RESPONSE: return ok(Backend.NoticeResponse(fields_of(data)?))
	if code == NOTIFICATION or code == NEGOTIATE_VERSION: return ok(Backend.Ignored)
	if code == PARSE_COMPLETE: return ok(Backend.ParseComplete)
	if code == BIND_COMPLETE: return ok(Backend.BindComplete)
	if code == CLOSE_COMPLETE: return ok(Backend.CloseComplete)
	if code == NO_DATA: return ok(Backend.NoData)
	if code == EMPTY_QUERY: return ok(Backend.EmptyQuery)
	if code == PORTAL_SUSPENDED: return ok(Backend.PortalSuspended)

	if code == PARAMETER_DESCRIPTION:
		count := u16(data, 0)?
		var oids = List[Int]()
		for i in 0..count: oids.append(u32(data, 2 + 4 * i)?)
		return ok(Backend.ParameterDescription(oids))

	return error(Error("postgres: unexpected message type {code}", kind: "EPROTO"))
