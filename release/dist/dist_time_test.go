// Copyright (c) Tailscale Inc & contributors
// SPDX-License-Identifier: BSD-3-Clause

package dist

import (
	"os"
	"testing"
	"time"
)

func TestBuildTimestampUsesCurrentTimeWhenSourceDateEpochUnset(t *testing.T) {
	previous, wasSet := os.LookupEnv("SOURCE_DATE_EPOCH")

	if err := os.Unsetenv("SOURCE_DATE_EPOCH"); err != nil {
		t.Fatalf("unsetting SOURCE_DATE_EPOCH: %v", err)
	}

	t.Cleanup(func() {
		var err error

		if wasSet {
			err = os.Setenv("SOURCE_DATE_EPOCH", previous)
		} else {
			err = os.Unsetenv("SOURCE_DATE_EPOCH")
		}

		if err != nil {
			t.Errorf("restoring SOURCE_DATE_EPOCH: %v", err)
		}
	})

	before := time.Now().UTC()

	got, err := buildTimestamp()
	if err != nil {
		t.Fatalf("buildTimestamp: %v", err)
	}

	after := time.Now().UTC()

	if got.Before(before) || got.After(after) {
		t.Fatalf(
			"buildTimestamp = %v, want a value between %v and %v",
			got,
			before,
			after,
		)
	}
}

func TestBuildTimestampUsesSourceDateEpoch(t *testing.T) {
	const sourceDateEpoch = "1785000000"

	t.Setenv("SOURCE_DATE_EPOCH", sourceDateEpoch)

	got, err := buildTimestamp()
	if err != nil {
		t.Fatalf("buildTimestamp: %v", err)
	}

	want := time.Unix(1785000000, 0).UTC()
	if !got.Equal(want) {
		t.Fatalf("buildTimestamp = %v, want %v", got, want)
	}

	if got.Location() != time.UTC {
		t.Fatalf("buildTimestamp location = %v, want UTC", got.Location())
	}
}

func TestBuildTimestampRejectsInvalidSourceDateEpoch(t *testing.T) {
	tests := []struct {
		name  string
		value string
	}{
		{
			name:  "empty",
			value: "",
		},
		{
			name:  "negative",
			value: "-1",
		},
		{
			name:  "not-a-number",
			value: "not-a-number",
		},
		{
			name:  "fractional",
			value: "1.5",
		},
		{
			name:  "overflow",
			value: "9223372036854775808",
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			t.Setenv("SOURCE_DATE_EPOCH", test.value)

			if _, err := buildTimestamp(); err == nil {
				t.Fatalf(
					"buildTimestamp accepted invalid SOURCE_DATE_EPOCH %q",
					test.value,
				)
			}
		})
	}
}
