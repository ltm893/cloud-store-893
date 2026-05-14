#!/usr/bin/env zsh
# Deprecated wrapper — use terraform-recover-workload-state.sh instead.
# This script never removed OCI compartments; it now forwards to the workload-only helper.
exec "${0:a:h}/terraform-recover-workload-state.sh" "$@"
