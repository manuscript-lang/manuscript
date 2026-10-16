package msruntime

import (
	"encoding/json"
	"testing"
)

func TestJsonScannerAgreesWithStandardValidity(t *testing.T) {
	cases := []string{
		`null`, `true`, `false`, `0`, `-0`, `1.5e+10`, `-12.0E-3`, `""`, `"a"`, `[]`, `{}`, ` [ 1 , 2 ] `, `{"a":{"b":[null,{}]}}`,
		`"é\n\t\"\\\/"`, `"😀"`, "\"tab\there\"", `[1,]`, `[,1]`, `{"a":1,}`, `{"a" 1}`, `{a:1}`, `01`, `1.`, `.5`, `+1`, `-`,
		`1e`, `1e+`, `nul`, `truee`, `[1 2]`, `{"a":1 "b":2}`, `"unterminated`, `"bad\x"`, `"\u12"`, `"\ud83d"`, `"\ude00"`,
		"\"raw\nnewline\"", `[`, `{`, `]`, ``, `   `, `1 2`, `[] []`, `{"a":1}x`, `"\ud83dx"`, `"\ud83dA"`,
	}
	for _, text := range cases {
		want := json.Valid([]byte(text)) && jsonUnicodeValid(nil, text)
		got := jsonParseTree(nil, text, Option[*JsonLimits]{})
		if got.Failed == want {
			t.Errorf("%q: valid=%v but parse failed=%v", text, want, got.Failed)
		}
	}
}

func TestJsonScannerDecodesStringsAndNumbers(t *testing.T) {
	tree := jsonParseTree(nil, `["aé\n","😀😀",12.50e1]`, Option[*JsonLimits]{})
	if tree.Failed {
		t.Fatal("parse failed")
	}
	items := tree.Val.(JsonValue_ArrayValue).Values.Items
	if got := items[0].(JsonValue_StringValue).Value; got != "aé\n" {
		t.Errorf("escapes: %q", got)
	}
	if got := items[1].(JsonValue_StringValue).Value; got != "😀😀" {
		t.Errorf("surrogates: %q", got)
	}
	if got := items[2].(JsonValue_NumberValue).Text; got != "12.50e1" {
		t.Errorf("number text: %q", got)
	}
}

func TestJsonScannerRejectsDuplicateKeys(t *testing.T) {
	if !jsonParseTree(nil, `{"a":1,"a":2}`, Option[*JsonLimits]{}).Failed {
		t.Error("duplicate keys accepted")
	}
}

func TestJsonNumberText(t *testing.T) {
	for text, want := range map[string]bool{"0": true, "-1.5e3": true, "": false, "01": false, "1.": false, "true": false, " 1": false, "1 ": false, "-": false} {
		if got := jsonNumberText(text); got != want {
			t.Errorf("%q: got %v want %v", text, got, want)
		}
	}
}
