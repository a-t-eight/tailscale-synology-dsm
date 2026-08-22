package synology

import (
	"bytes"
	"log"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"tailscale.com/release/dist"
	"tailscale.com/version/mkversion"
)

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
		"pkg_min_ver=1.1.0-3\n" +
		"os_min_ver=7.3-86009\n"
	if string(got) != want {
		t.Fatalf("PKG_DEPS mismatch\n got: %q\nwant: %q", got, want)
	}
	if strings.Contains(string(got), "tailscale-netfilter-modules") {
		t.Fatal("old dependency remains")
	}
}
