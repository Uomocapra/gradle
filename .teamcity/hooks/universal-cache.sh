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
# ============================================================================
# TEMPORARY — TESTING ONLY. DO NOT KEEP.
#
# This is a copy of dev-infrastructure's universal-cache.sh (gradle/dev-infrastructure#3163),
# committed here so the smoke-test artifact-cache hooks can be exercised on CI BEFORE a new
# agent AMI is baked that bakes this script and publishes GRADLE_UNIVERSAL_CACHE_CLI_PATH.
# Once that AMI ships, delete this file and the fallback in hooks.sh — the agent provides the
# real contract and gradle/gradle must not carry CLI/AMI knowledge.
#
# Difference from the canonical copy: the canonical script resolves common.sh and the CLI jar
# next to itself (in the agent hooks dir). Here it lives in the repo, so it resolves both from
# the agent hooks dir (${HOME}/agent/hooks), which the existing AMI already bakes.
# ============================================================================
#
# Usage:
#   universal-cache.sh (--store|--restore) <image-name> <gradle-home>

set -euo pipefail

usage() {
  echo "Usage: $(basename "$0") (--store|--restore) <image-name> <gradle-home>" >&2
  exit 2
}

OPERATION=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --store) OPERATION="store"; shift ;;
    --restore) OPERATION="restore"; shift ;;
    --) shift; break ;;
    -*) echo "Unknown option: $1" >&2; usage ;;
    *) break ;;
  esac
done

[[ "${OPERATION}" == "store" || "${OPERATION}" == "restore" ]] || usage
[[ $# -eq 2 ]] || usage
IMAGE_NAME="$1"
GRADLE_HOME="$2"

# The existing AMI bakes the Artifact Cache CLI jar and common.sh (AC_CLI_VERSION,
# assertDevelocityServerUrl) into the agent hooks dir.
AGENT_HOOKS_DIR="${HOME}/agent/hooks"
if [ ! -d "${AGENT_HOOKS_DIR}" ]; then
  echo "ERROR: agent hooks directory ${AGENT_HOOKS_DIR} not found." >&2
  exit 1
fi
# shellcheck source=/dev/null
source "${AGENT_HOOKS_DIR}/common.sh"

AC_CLI_JAR="${AGENT_HOOKS_DIR}/develocity-artifact-cache-cli-${AC_CLI_VERSION}.jar"
if [ ! -f "${AC_CLI_JAR}" ]; then
  echo "ERROR: Develocity Artifact Cache CLI jar not found at ${AC_CLI_JAR}." >&2
  exit 1
fi

assertDevelocityServerUrl

REPORTING_DIR="artifact-cache-report/${OPERATION}/${IMAGE_NAME}"
CACHE_METRICS_FILE="artifact-cache-metrics/${OPERATION}-${IMAGE_NAME}.json"

echo "Artifact cache ${OPERATION}: image='${IMAGE_NAME}' gradle-home='${GRADLE_HOME}'"
start_time="$(date +%s)000"

# The CLI requires Java 21; run it with the AMI's pinned JDK regardless of the build's JAVA_HOME.
set +e
"/opt/jdk/open-jdk-21/bin/java" -jar "${AC_CLI_JAR}" \
  "${OPERATION}" \
  --dv-edge="${DEVELOCITY_SERVER_URL}" \
  --image-name="${IMAGE_NAME}" \
  --gradle-home="${GRADLE_HOME}" \
  --reporting-directory="${REPORTING_DIR}" \
  --cache-metrics-file="${CACHE_METRICS_FILE}" \
  --operation-timeout=PT10M \
  --verbose
exitCode=$?
set -e

end_time="$(date +%s)000"
echo "Artifact cache ${OPERATION} for image '${IMAGE_NAME}' finished in $((end_time - start_time)) ms with exit code ${exitCode}."
exit "${exitCode}"
