#!/bin/bash
#
# Copyright 2026 the original author or authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Repository build hook for the integration-test Gradle user home (intTestHomeDir).
# Restores (pre) or stores (post) each distribution home via the artifact-cache contract
# the CI agent provides. The agent publishes that contract's path as
# GRADLE_UNIVERSAL_CACHE_CLI_PATH; this hook knows nothing about the CLI itself. When the
# variable is absent (local builds, non-EC2 agents) the hook does nothing.
#
# Usage: hooks.sh (pre|post)   -- invoked by the thin pre-build/post-build shims.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PHASE="${1:-}"
case "${PHASE}" in
  pre|post) ;;
  *) echo "Usage: $(basename "$0") (pre|post)" >&2; exit 2 ;;
esac

# Only smoke tests share the integration-test Gradle user home, so only they benefit here.
if [[ "${BUILD_TYPE_ID:-}" != *SmokeTest* ]]; then
  echo "Skipping artifact cache: BUILD_TYPE_ID='${BUILD_TYPE_ID:-}' is not a SmokeTest build."
  exit 0
fi

# The CI agent provides the artifact-cache contract via GRADLE_UNIVERSAL_CACHE_CLI_PATH.
# TEMPORARY (testing): until a new AMI is baked that publishes that variable, fall back to the
# universal-cache.sh copy committed alongside this hook (see dev-infrastructure#3163). Remove
# this fallback and the committed universal-cache.sh once the AMI ships.
CACHE_CLI="${GRADLE_UNIVERSAL_CACHE_CLI_PATH:-${SCRIPT_DIR}/universal-cache.sh}"
if [[ ! -x "${CACHE_CLI}" ]]; then
  echo "Skipping artifact cache: no usable artifact-cache CLI (GRADLE_UNIVERSAL_CACHE_CLI_PATH unset and no local universal-cache.sh)."
  exit 0
fi

INT_TEST_HOME_DIR="$(pwd)/intTestHomeDir"
# Homes to restore; on store we only pick up the ones that were populated.
INT_TEST_DISTRIBUTIONS="${INT_TEST_DISTRIBUTIONS:-full jvm basics native}"

# Image name, stable across builds of the same base branch (release vs master).
if [[ "${BUILD_TYPE_ID:-}" == Gradle_Release* ]]; then
  baseBranch="release"
else
  baseBranch="master"
fi

for dist in ${INT_TEST_DISTRIBUTIONS}; do
  gradleHome="${INT_TEST_HOME_DIR}/distributions-${dist}"
  imageName="gradle-SmokeTest-${baseBranch}-distributions-${dist}"

  if [[ "${PHASE}" == "pre" ]]; then
    mkdir -p "${gradleHome}"
    echo "Restoring integration-test Gradle user home '${gradleHome}' from image '${imageName}'..."
    # Best-effort: a miss or error just means tests download as before.
    "${CACHE_CLI}" --restore "${imageName}" "${gradleHome}" || true

    # The Artifact Cache CLI unconditionally injects an init script
    # (init.d/develocity-inject-restore-metrics.gradle) into every restored Gradle home to
    # report cache metrics to the build scan; there is no CLI flag to disable it. Smoke tests
    # reuse this home for their *nested* builds, where that script runs too. It is incompatible
    # with the older Develocity plugin versions the smoke tests exercise (it NPEs on a null
    # buildScan), and its stack trace pollutes the nested build output, which the smoke-test
    # runner rejects. We only want the dependency cache here, not the metrics instrumentation,
    # so remove the injected init script after restore.
    rm -f "${gradleHome}/init.d/develocity-inject-restore-metrics.gradle"
  elif [ -d "${gradleHome}/caches/modules-2" ]; then
    echo "Storing integration-test Gradle user home '${gradleHome}' to image '${imageName}'..."
    "${CACHE_CLI}" --store "${imageName}" "${gradleHome}" || true
  fi
done
