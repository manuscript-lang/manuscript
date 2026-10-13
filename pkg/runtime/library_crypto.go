package msruntime

import (
	"bytes"
	"compress/flate"
	"compress/gzip"
	"compress/zlib"
	"crypto/aes"
	"crypto/cipher"
	"crypto/ed25519"
	"crypto/hmac"
	"crypto/sha256"
	"crypto/sha512"
	"crypto/subtle"
	"hash"
	"io"
)

func init() {
	p := func(n, t string) LibraryParam { return LibraryParam{n, t} }
	for _, algorithm := range []string{"sha256", "sha384", "sha512"} {
		libraryAdd("crypto", algorithm, "Bytes", []LibraryParam{p("data", "Bytes")}, func(ctx *Execution, _ string, a []Value) Value {
			h := libraryHash(algorithm)
			libraryHashWrite(ctx, h, a[0].(Bytes).Items)
			return Bytes{h.Sum(nil)}
		})
	}
	libraryAdd("crypto", "hmac", libraryResult("Bytes", "CryptoError"), []LibraryParam{p("key", "Bytes"), p("data", "Bytes"), p("algorithm", "String")}, func(ctx *Execution, r string, a []Value) Value {
		algorithm := a[2].(string)
		if libraryHash(algorithm) == nil {
			return libraryError(r, "Unsupported", "")
		}
		h := hmac.New(func() hash.Hash { return libraryHash(algorithm) }, a[0].(Bytes).Items)
		libraryHashWrite(ctx, h, a[1].(Bytes).Items)
		return libraryOK(r, Bytes{h.Sum(nil)})
	})
	libraryAdd("crypto", "constant_time_equal", "Bool", []LibraryParam{p("left", "Bytes"), p("right", "Bytes")}, func(_ *Execution, _ string, a []Value) Value {
		return subtle.ConstantTimeCompare(a[0].(Bytes).Items, a[1].(Bytes).Items) == 1
	})
	libraryAdd("crypto", "derive_key", libraryResult("Bytes", "CryptoError"), []LibraryParam{p("password", "Bytes"), p("salt", "Bytes"), p("iterations", "Int"), p("length", "Int")}, libraryPBKDF2)
	libraryAdd("crypto", "seal", libraryResult("Bytes", "CryptoError"), []LibraryParam{p("key", "Bytes"), p("nonce", "Bytes"), p("plaintext", "Bytes"), p("associated_data", "Bytes")}, func(_ *Execution, r string, a []Value) Value {
		g, err := libraryAEAD(a[0].(Bytes).Items)
		nonce := a[1].(Bytes).Items
		data := a[2].(Bytes).Items
		if err != nil || len(nonce) != 12 || uint64(len(data)) > ((1<<32)-2)*16 {
			return libraryError(r, "InvalidInput", "")
		}
		return libraryOK(r, Bytes{g.Seal(nil, nonce, data, a[3].(Bytes).Items)})
	})
	libraryAdd("crypto", "open", libraryResult("Bytes", "CryptoError"), []LibraryParam{p("key", "Bytes"), p("nonce", "Bytes"), p("ciphertext", "Bytes"), p("associated_data", "Bytes")}, func(_ *Execution, r string, a []Value) Value {
		g, err := libraryAEAD(a[0].(Bytes).Items)
		nonce := a[1].(Bytes).Items
		if err != nil || len(nonce) != 12 {
			return libraryError(r, "InvalidInput", "")
		}
		b, err := g.Open(nil, nonce, a[2].(Bytes).Items, a[3].(Bytes).Items)
		if err != nil {
			return libraryError(r, "AuthenticationFailed", "")
		}
		return libraryOK(r, Bytes{b})
	})
	libraryAdd("crypto", "sign", libraryResult("Bytes", "CryptoError"), []LibraryParam{p("seed", "Bytes"), p("data", "Bytes")}, func(_ *Execution, r string, a []Value) Value {
		seed := a[0].(Bytes).Items
		if len(seed) != ed25519.SeedSize {
			return libraryError(r, "InvalidInput", "")
		}
		return libraryOK(r, Bytes{ed25519.Sign(ed25519.NewKeyFromSeed(seed), a[1].(Bytes).Items)})
	})
	libraryAdd("crypto", "public_key", libraryResult("Bytes", "CryptoError"), []LibraryParam{p("seed", "Bytes")}, func(_ *Execution, r string, a []Value) Value {
		seed := a[0].(Bytes).Items
		if len(seed) != ed25519.SeedSize {
			return libraryError(r, "InvalidInput", "")
		}
		key := ed25519.NewKeyFromSeed(seed).Public().(ed25519.PublicKey)
		return libraryOK(r, Bytes{append([]byte{}, key...)})
	})
	libraryAdd("crypto", "verify", "Bool", []LibraryParam{p("key", "Bytes"), p("data", "Bytes"), p("signature", "Bytes")}, func(_ *Execution, _ string, a []Value) Value {
		key := a[0].(Bytes).Items
		if len(key) != ed25519.PublicKeySize {
			return false
		}
		return ed25519.Verify(key, a[1].(Bytes).Items, a[2].(Bytes).Items)
	})
	libraryAdd("compress", "compress", libraryResult("Bytes", "CompressionError"), []LibraryParam{p("data", "Bytes"), p("format", "String"), p("level", "Int"), p("max_bytes", "Optional[Int]")}, libraryCompress)
	libraryAdd("compress", "decompress", libraryResult("Bytes", "CompressionError"), []LibraryParam{p("data", "Bytes"), p("format", "String"), p("max_bytes", "Optional[Int]")}, libraryDecompress)
}
func libraryHash(algorithm string) hash.Hash {
	switch algorithm {
	case "sha256":
		return sha256.New()
	case "sha384":
		return sha512.New384()
	case "sha512":
		return sha512.New()
	}
	return nil
}
func libraryHashWrite(ctx *Execution, h hash.Hash, data []byte) {
	for len(data) > 0 {
		CheckCancelled(ctx)
		n := len(data)
		if n > 65536 {
			n = 65536
		}
		h.Write(data[:n])
		data = data[n:]
	}
}
func libraryAEAD(key []byte) (cipher.AEAD, error) {
	if len(key) != 32 {
		return nil, io.ErrUnexpectedEOF
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, err
	}
	return cipher.NewGCM(block)
}
func libraryPBKDF2(ctx *Execution, r string, a []Value) Value {
	iterations, length := a[2].(int64), a[3].(int64)
	if iterations <= 0 || length <= 0 || length > 1048576 {
		return libraryError(r, "InvalidInput", "")
	}
	password, salt := a[0].(Bytes).Items, a[1].(Bytes).Items
	out := make([]byte, 0, int(length))
	for block := uint32(1); int64(len(out)) < length; block++ {
		CheckCancelled(ctx)
		h := hmac.New(sha256.New, password)
		h.Write(salt)
		h.Write([]byte{byte(block >> 24), byte(block >> 16), byte(block >> 8), byte(block)})
		u := h.Sum(nil)
		t := append([]byte{}, u...)
		for i := int64(1); i < iterations; i++ {
			if i%256 == 0 {
				CheckCancelled(ctx)
			}
			h.Reset()
			h.Write(u)
			u = h.Sum(u[:0])
			for j := range t {
				t[j] ^= u[j]
			}
		}
		n := int64(len(t))
		if n > length-int64(len(out)) {
			n = length - int64(len(out))
		}
		out = append(out, t[:n]...)
	}
	return libraryOK(r, Bytes{out})
}
func libraryCompress(ctx *Execution, r string, a []Value) Value {
	level, max := a[2].(int64), a[3].(int64)
	if level < 0 || level > 9 || max < 0 {
		return libraryError(r, "InvalidInput", "")
	}
	w := &libraryLimitedWriter{max: max}
	var writer io.WriteCloser
	var err error
	switch a[1].(string) {
	case "gzip":
		writer, err = gzip.NewWriterLevel(w, int(level))
	case "zlib":
		writer, err = zlib.NewWriterLevel(w, int(level))
	case "deflate":
		writer, err = flate.NewWriter(w, int(level))
	default:
		return libraryError(r, "Unsupported", "")
	}
	if err != nil {
		return libraryError(r, "InvalidInput", "")
	}
	defer writer.Close()
	data := a[0].(Bytes).Items
	for len(data) > 0 {
		CheckCancelled(ctx)
		n := len(data)
		if n > 65536 {
			n = 65536
		}
		if _, err = writer.Write(data[:n]); err != nil {
			return libraryError(r, "LimitExceeded", "")
		}
		data = data[n:]
	}
	if err = writer.Close(); err != nil {
		return libraryError(r, "LimitExceeded", "")
	}
	return libraryOK(r, Bytes{append([]byte{}, w.Bytes()...)})
}
func libraryDecompress(ctx *Execution, r string, a []Value) Value {
	max := a[2].(int64)
	if max < 0 {
		return libraryError(r, "InvalidInput", "")
	}
	input := bytes.NewReader(a[0].(Bytes).Items)
	var reader io.ReadCloser
	var err error
	switch a[1].(string) {
	case "gzip":
		reader, err = gzip.NewReader(input)
	case "zlib":
		reader, err = zlib.NewReader(input)
	case "deflate":
		reader = flate.NewReader(input)
	default:
		return libraryError(r, "Unsupported", "")
	}
	if err != nil {
		return libraryError(r, "InvalidData", "")
	}
	defer reader.Close()
	b, code := libraryReadBounded(ctx, reader, max)
	if code != "" {
		return libraryError(r, code, "")
	}
	if input.Len() != 0 {
		return libraryError(r, "InvalidData", "")
	}
	return libraryOK(r, Bytes{b})
}
func libraryReadBounded(ctx *Execution, reader io.Reader, max int64) ([]byte, string) {
	var out bytes.Buffer
	buffer := make([]byte, 32768)
	for {
		CheckCancelled(ctx)
		remaining := max - int64(out.Len())
		chunk := buffer
		if remaining < int64(len(buffer)) {
			chunk = buffer[:int(remaining)+1]
		}
		n, err := reader.Read(chunk)
		if int64(n) > remaining {
			return nil, "LimitExceeded"
		}
		out.Write(chunk[:n])
		if err == io.EOF {
			return out.Bytes(), ""
		}
		if err != nil {
			return nil, "InvalidData"
		}
		if n == 0 {
			return nil, "Failed"
		}
	}
}
