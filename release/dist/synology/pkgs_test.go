// Copyright (c) Tailscale Inc & contributors
// SPDX-License-Identifier: BSD-3-Clause

package synology

import (
	"archive/tar"
	"bytes"
	"encoding/json"
	"io"
	"log"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"tailscale.com/release/dist"
	"tailscale.com/version/mkversion"
)

func TestDSM7InnerStaticEntriesIncludeBootstrap(t *testing.T) {
	var buf bytes.Buffer
	tw := tar.NewWriter(&buf)
	if err := writeTar(tw, time.Unix(0, 0), innerPackageStaticEntries(7)...); err != nil {
		t.Fatal(err)
	}
	if err := tw.Close(); err != nil {
		t.Fatal(err)
	}

	want, err := files.ReadFile("files/scripts/tailscale-synology-bootstrap")
	if err != nil {
		t.Fatal(err)
	}

	tr := tar.NewReader(bytes.NewReader(buf.Bytes()))
	for {
		hdr, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			t.Fatal(err)
		}
		if hdr.Name != "bin/tailscale-synology-bootstrap" {
			continue
		}
		if got := hdr.FileInfo().Mode().Perm(); got != 0755 {
			t.Fatalf("bootstrap mode=%#o, want 0755", got)
		}
		got, err := io.ReadAll(tr)
		if err != nil {
			t.Fatal(err)
		}
		if !bytes.Equal(got, want) {
			t.Fatal("inner bootstrap content differs from canonical script source")
		}
		return
	}

	t.Fatal("inner package entries do not contain bin/tailscale-synology-bootstrap")
}

func TestDSM7BootstrapIntegrationMetadata(t *testing.T) {
	resourceBytes, err := files.ReadFile("files/resource")
	if err != nil {
		t.Fatal(err)
	}
	var resource struct {
		UsrLocalLinker struct {
			Bin []string `json:"bin"`
		} `json:"usr-local-linker"`
	}
	if err := json.Unmarshal(resourceBytes, &resource); err != nil {
		t.Fatal(err)
	}
	if !containsString(resource.UsrLocalLinker.Bin, "bin/tailscale-synology-bootstrap") {
		t.Fatalf("usr-local-linker bin=%q, missing bootstrap", resource.UsrLocalLinker.Bin)
	}

	for _, test := range []struct {
		name          string
		wantToolPaths []string
	}{
		{name: "privilege-dsm7"},
		{
			name:          "privilege-dsm7.for-package-center",
			wantToolPaths: []string{"bin/tailscaled"},
		},
	} {
		privilegeBytes, err := files.ReadFile("files/" + test.name)
		if err != nil {
			t.Fatal(err)
		}
		var privilege struct {
			Tool []struct {
				Relpath string `json:"relpath"`
			} `json:"tool"`
		}
		if err := json.Unmarshal(privilegeBytes, &privilege); err != nil {
			t.Fatal(err)
		}
		var gotToolPaths []string
		for _, tool := range privilege.Tool {
			gotToolPaths = append(gotToolPaths, tool.Relpath)
		}
		if strings.Join(gotToolPaths, "\n") != strings.Join(test.wantToolPaths, "\n") {
			t.Fatalf("%s tool paths=%q, want %q", test.name, gotToolPaths, test.wantToolPaths)
		}
	}
}

func containsString(values []string, want string) bool {
	for _, value := range values {
		if value == want {
			return true
		}
	}
	return false
}

func r2TestBuild() *dist.Build {
	return &dist.Build{Version: mkversion.VersionInfo{
		Short: "1.98.96",
		Synology: map[int]int64{
			70: 700098096,
			72: 720098096,
		},
	}}
}

func TestSynologyPackageRevision(t *testing.T) {
	if synologyPackageRevision != 2 {
		t.Fatalf("revision=%d, want 2", synologyPackageRevision)
	}
	for base, want := range map[int64]int64{
		700098096: 700098097,
		720098096: 720098097,
	} {
		if got := synologyPackageBuildNumber(base); got != want {
			t.Fatalf("build(%d)=%d, want %d", base, got, want)
		}
		if want <= base {
			t.Fatalf("r2 build %d is not newer than r1 %d", want, base)
		}
	}
}

func TestDSM7R2Info(t *testing.T) {
	tests := []struct {
		name   string
		target target
		want   string
	}{
		{"sideload", target{dsmMajorVersion: 7}, `version="1.98.96-700098097"`},
		{"package-center", target{dsmMajorVersion: 7, dsmMinorVersion: 2, packageCenter: true}, `version="1.98.96-720098097"`},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			info := string(tt.target.mkInfo(r2TestBuild(), 0))
			for _, want := range []string{tt.want, `os_min_ver="7.3-86009"`} {
				if !strings.Contains(info, want+"\n") {
					t.Fatalf("INFO missing %q:\n%s", want, info)
				}
			}
			if strings.Contains(info, "os_max_ver=") {
				t.Fatalf("INFO must omit os_max_ver:\n%s", info)
			}
		})
	}
}

func TestDSM7R2SPKFilenames(t *testing.T) {
	tests := []struct {
		name   string
		target target
		want   string
	}{
		{
			"sideload",
			target{filenameArch: "x86_64", dsmMajorVersion: 7},
			"tailscale-x86_64-1.98.96-700098097-dsm7.spk",
		},
		{
			"package-center",
			target{filenameArch: "x86_64", dsmMajorVersion: 7, dsmMinorVersion: 2, packageCenter: true},
			"tailscale-x86_64-1.98.96-720098097-dsm7-2.spk",
		},
	}
	previousLogOutput := log.Writer()
	t.Cleanup(func() { log.SetOutput(previousLogOutput) })
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var logOutput bytes.Buffer
			log.SetOutput(&logOutput)

			build := r2TestBuild()
			build.Out = filepath.Join(t.TempDir(), "missing")
			_, err := tt.target.buildSPK(build, &innerPkg{})
			if !os.IsNotExist(err) {
				t.Fatalf("buildSPK error=%v, want missing-output-directory error", err)
			}
			if !strings.Contains(logOutput.String(), tt.want) {
				t.Fatalf("buildSPK log missing filename %q: %s", tt.want, logOutput.String())
			}
			if _, err := os.Stat(filepath.Join(build.Out, tt.want)); !os.IsNotExist(err) {
				t.Fatalf("buildSPK unexpectedly created %q: %v", tt.want, err)
			}
		})
	}
}

func TestLegacyDSMInfoRanges(t *testing.T) {
	tests := []struct {
		name    string
		target  target
		wantMin string
		wantMax string
	}{
		{
			"dsm6-package-center",
			target{dsmMajorVersion: 6, packageCenter: true},
			`os_min_ver="6.0.1-7445"`,
			`os_max_ver="7.0-40000"`,
		},
		{
			"dsm7-package-center",
			target{dsmMajorVersion: 7, packageCenter: true},
			`os_min_ver="7.0-40000"`,
			`os_max_ver="7.2-60000"`,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			info := string(tt.target.mkInfo(r2TestBuild(), 0))
			for prefix, want := range map[string]string{
				"os_min_ver=": tt.wantMin,
				"os_max_ver=": tt.wantMax,
			} {
				var matches []string
				for _, line := range strings.Split(info, "\n") {
					if strings.HasPrefix(line, prefix) {
						matches = append(matches, line)
					}
				}
				if len(matches) != 1 || matches[0] != want {
					t.Fatalf("INFO %s entries=%q, want [%q]:\n%s", prefix, matches, want, info)
				}
			}
		})
	}
}

func TestR2PKGDeps(t *testing.T) {
	got, err := files.ReadFile("files/PKG_DEPS")
	if err != nil {
		t.Fatal(err)
	}
	want := "[iptables-netfilter-extensions]\n" +
		"pkg_min_ver=1.1.0-2\n" +
		"os_min_ver=7.3-86009\n"
	if string(got) != want {
		t.Fatalf("PKG_DEPS mismatch\n got: %q\nwant: %q", got, want)
	}
	if strings.Contains(string(got), "tailscale-netfilter-modules") {
		t.Fatal("old dependency remains")
	}
}
