package offline

import (
	"bytes"
	"encoding/json"
	"errors"
	"io"
)

// Reject ambiguous duplicate members and trailing objects before any SDK use.
func CheckJSON(raw []byte) error {
	d := json.NewDecoder(bytes.NewReader(raw))
	d.UseNumber()
	var walk func() error
	walk = func() error {
		token, e := d.Token()
		if e != nil {
			return e
		}
		delimiter, ok := token.(json.Delim)
		if !ok {
			return nil
		}
		switch delimiter {
		case '{':
			seen := map[string]bool{}
			for d.More() {
				key, e := d.Token()
				if e != nil {
					return e
				}
				s, ok := key.(string)
				if !ok || seen[s] {
					return errors.New("duplicate/non-string JSON member")
				}
				seen[s] = true
				if e = walk(); e != nil {
					return e
				}
			}
		case '[':
			for d.More() {
				if e = walk(); e != nil {
					return e
				}
			}
		default:
			return errors.New("unexpected JSON delimiter")
		}
		_, e = d.Token()
		return e
	}
	if e := walk(); e != nil {
		return e
	}
	if _, e := d.Token(); e != io.EOF {
		return errors.New("one complete JSON value required")
	}
	return nil
}
func StrictJSON(raw []byte, target any) error {
	if e := CheckJSON(raw); e != nil {
		return e
	}
	d := json.NewDecoder(bytes.NewReader(raw))
	d.DisallowUnknownFields()
	return d.Decode(target)
}
