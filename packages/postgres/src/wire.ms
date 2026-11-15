// PostgreSQL frontend/backend protocol v3: message encoding and decoding, in pure
// Manuscript.
import Bytes, BytesBuilder from "@std/bytes.ms"

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
	ReadyForQuery(status: Int)
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
	Other(code: Int)

fn framed(code: Int, body: Bytes) Bytes:
	var out = BytesBuilder()
	out.append(code.to_uint8().get(0))
	out.append_int32_be((body.length() + 4).to_int32().get(0))
	out.append_bytes(body)
	return out.build()

fn cstring(var out: BytesBuilder, text: String) Unit:
	out.append_bytes(text.to_bytes())
	out.append(0)

// The startup message, sent first; it has no type byte.
export fn startup(user: String, database: String, options: Map[String, String]) Bytes:
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
	out.append_int32_be((payload.length() + 4).to_int32().get(0))
	out.append_bytes(payload)
	return out.build()

// Asks the server to switch to TLS.
export fn ssl_request() Bytes:
	var out = BytesBuilder()
	out.append_int32_be(8)
	out.append_int32_be(80877103)
	return out.build()

export fn terminate() Bytes:
	return framed(88, Bytes([]))

export fn sync() Bytes:
	return framed(83, Bytes([]))

export fn query(sql: String) Bytes:
	var body = BytesBuilder()
	cstring(var body, sql)
	return framed(81, body.build())

export fn password(text: String) Bytes:
	var body = BytesBuilder()
	cstring(var body, text)
	return framed(112, body.build())

// SASLInitialResponse: mechanism name and the client-first message.
export fn sasl_initial(mechanism: String, first: Bytes) Bytes:
	var body = BytesBuilder()
	cstring(var body, mechanism)
	body.append_int32_be(first.length().to_int32().get(0))
	body.append_bytes(first)
	return framed(112, body.build())

export fn sasl_response(data: Bytes) Bytes:
	return framed(112, data)

export fn parse(name: String, sql: String, oids: List[Int]) Bytes:
	var body = BytesBuilder()
	cstring(var body, name)
	cstring(var body, sql)
	body.append_int16_be(oids.length().to_int16().get(0))
	for oid in oids: body.append_int32_be(oid.to_int32().get(0))
	return framed(80, body.build())

// Bind with text-format parameters (none means NULL) and binary or text results.
export fn bind(
	portal: String,
	name: String,
	params: List[Bytes?],
	result_binary: Bool,
) Bytes:
	var body = BytesBuilder()
	cstring(var body, portal)
	cstring(var body, name)
	body.append_int16_be(0)
	body.append_int16_be(params.length().to_int16().get(0))

	for param in params:
		if value := param:
			body.append_int32_be(value.length().to_int32().get(0))
			body.append_bytes(value)
		else:
			body.append_int32_be(-1)

	body.append_int16_be(1)
	body.append_int16_be(if result_binary: 1 else: 0)
	return framed(66, body.build())

// Describes a statement (`S`) or a portal (`P`).
export fn describe(kind: UInt8, name: String) Bytes:
	var body = BytesBuilder()
	body.append(kind)
	cstring(var body, name)
	return framed(68, body.build())

export fn close_statement(name: String) Bytes:
	var body = BytesBuilder()
	body.append(83)
	cstring(var body, name)
	return framed(67, body.build())

export fn execute(portal: String, max_rows: Int) Bytes:
	var body = BytesBuilder()
	cstring(var body, portal)
	body.append_int32_be(max_rows.to_int32().get(0))
	return framed(69, body.build())

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
	end := data.index_of_byte(0, at)
	if end.is_none(): return error(bad("string"))

	stop := end.get(0)
	return ok(CString(data.decode_utf8_range(at, stop).get(""), stop + 1))

fn fields_of(data: Bytes) Map[String, String]!:
	var out = Map[String, String]()
	var at = 0

	while at < data.length():
		code := data.get(at)
		if code == 0: break

		entry := read_cstring(data, at + 1)?
		out.add(Bytes([code]).decode_utf8().get(""), entry.text.clone())
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

// Decodes the body of one backend message with type byte `code`.
export fn decode_message(code: Int, data: Bytes) Backend!:
	if code == 82:
		kind := i32(data, 0)?
		if kind == 0: return ok(Backend.AuthOk)
		if kind == 3: return ok(Backend.AuthCleartext)
		if kind == 5: return ok(Backend.AuthMd5(data.slice(4, 8)?))
		if kind == 11 or kind == 12: return ok(
			if kind == 11: Backend.AuthSaslContinue(
				data.slice(4, data.length())?
			) else: Backend.AuthSaslFinal(data.slice(4, data.length())?)
		)

		if kind == 10:
			var names = List[String]()
			var at = 4

			while at < data.length() and data.get(at) != 0:
				entry := read_cstring(data, at)?
				names.append(entry.text.clone())
				at = entry.next

			return ok(Backend.AuthSasl(names))

		return error(
			Error(
				"postgres: unsupported authentication method {kind}",
				kind: "ENOTSUP",
			)
		)

	if code == 83:
		name := read_cstring(data, 0)?
		value := read_cstring(data, name.next)?
		return ok(Backend.ParameterStatus(name.text.clone(), value.text.clone()))

	if code == 75: return ok(Backend.BackendKeyData(i32(data, 0)?, i32(data, 4)?))
	if code == 90: return ok(Backend.ReadyForQuery(data.get(0).to_int()))
	if code == 84: return row_description(data)
	if code == 68: return data_row(data)

	if code == 67:
		tag := read_cstring(data, 0)?
		return ok(Backend.CommandComplete(tag.text.clone()))

	if code == 69: return ok(Backend.ErrorResponse(fields_of(data)?))
	if code == 78: return ok(Backend.NoticeResponse(fields_of(data)?))
	if code == 49: return ok(Backend.ParseComplete)
	if code == 50: return ok(Backend.BindComplete)
	if code == 51: return ok(Backend.CloseComplete)
	if code == 110: return ok(Backend.NoData)
	if code == 73: return ok(Backend.EmptyQuery)
	if code == 115: return ok(Backend.PortalSuspended)

	if code == 116:
		count := u16(data, 0)?
		var oids = List[Int]()
		for i in 0..count: oids.append(u32(data, 2 + 4 * i)?)
		return ok(Backend.ParameterDescription(oids))

	return ok(Backend.Other(code))
