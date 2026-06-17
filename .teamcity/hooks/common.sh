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
# Shared helpers for the pre-build/post-build hooks, which restore/store the integration-test Gradle
# user home (intTestHomeDir) via the Develocity Artifact Cache CLI. Run by the teamcity-hooks-plugin
# with cwd set to the checkout directory.

# shellcheck disable=SC2034  # used by the sourcing pre-build/post-build hooks
INT_TEST_HOME_DIR="$(pwd)/intTestHomeDir"

# Homes to restore; on store we only pick up the ones that exist.
INT_TEST_DISTRIBUTIONS="${INT_TEST_DISTRIBUTIONS:-full jvm basics native}"

# The agent-wide hooks directory baked by dev-infrastructure.
AGENT_HOOKS_DIR="${HOME}/agent/hooks"

# https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-metadata.html
isEc2Instance() {
  curl -m 1 -s -f "http://169.254.169.254/latest/meta-data/instance-id" >/dev/null 2>&1
}

baseBranchName() {
  if [[ "${BUILD_TYPE_ID:-}" == Gradle_Release* ]]; then
    echo "release"
  else
    echo "master"
  fi
}

# Image name for a distribution home, stable across builds of the same base branch.
imageNameFor() {
  echo "gradle-integtest-$(baseBranchName)-distributions-$1"
}

# Guard shared by both hooks: skips (returns non-zero) unless this is a SmokeTest build on an EC2
# agent with the baked Artifact Cache CLI. On success, sources the agent common.sh and sets AC_CLI_JAR
# and AC_CLI_JAVA.
setUpArtifactCache() {
  if [[ "${BUILD_TYPE_ID:-}" != *SmokeTest* ]]; then
    echo "Skipping artifact cache: BUILD_TYPE_ID='${BUILD_TYPE_ID:-}' is not a SmokeTest build."
    return 1
  fi
  if ! isEc2Instance; then
    echo "Skipping artifact cache: not running on an EC2 instance."
    return 1
  fi
  if [ ! -d "${AGENT_HOOKS_DIR}" ]; then
    echo "Skipping artifact cache: agent hooks directory ${AGENT_HOOKS_DIR} not found."
    return 1
  fi
  # Reuse the agent-wide common.sh (assertDevelocityServerUrl, ...).
  # shellcheck source=/dev/null
  source "${AGENT_HOOKS_DIR}/common.sh"

  local jars=("${AGENT_HOOKS_DIR}"/develocity-artifact-cache-cli-*.jar)
  AC_CLI_JAR="${jars[0]}"
  if [ ! -f "${AC_CLI_JAR}" ]; then
    echo "Skipping artifact cache: Develocity Artifact Cache CLI jar not found in ${AGENT_HOOKS_DIR}."
    return 1
  fi
  # The CLI requires Java 21; JAVA_HOME may be older (e.g. 17 for these smoke tests), so use JDK_21_0.
  if [ -z "${JDK_21_0:-}" ]; then
    echo "Skipping artifact cache: JDK_21_0 is not set."
    return 1
  fi
  # shellcheck disable=SC2034  # used by the sourcing pre-build/post-build hooks
  AC_CLI_JAVA="${JDK_21_0}/bin/java"

  assertDevelocityServerUrl
}
