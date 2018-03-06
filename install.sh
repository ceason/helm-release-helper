#!/usr/bin/env bash
[ "$HELM_DEBUG" = "1" ] && set -x
set -euo pipefail
err_report() { echo "errexit on line $(caller)" >&2; }
trap err_report ERR

if ! grep -q '^diff ' <("$HELM_BIN" plugin list); then
	helm_diff=https://github.com/databus23/helm-diff
	echo "Installing 'helm-diff' plugin: $helm_diff"
	$HELM_BIN plugin install $helm_diff
fi

