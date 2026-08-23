// Copyright (c) Tailscale Inc & contributors
// SPDX-License-Identifier: BSD-3-Clause

package synology

const synologyPackageRevision int64 = 2

func synologyPackageBuildNumber(base int64) int64 {
	if synologyPackageRevision < 1 {
		panic("Synology package revision must be positive")
	}
	return base + synologyPackageRevision - 1
}
