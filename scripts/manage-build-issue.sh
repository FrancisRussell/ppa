#!/usr/bin/env bash
# Opens or closes a GitHub issue tracking a build failure for a given
# package/codename/arch combination. Called from the manage-issues CI job.
# Usage: manage-build-issue.sh <status> <package> <codename> <arch>
set -euo pipefail

STATUS="${1?status required}"
PACKAGE="${2?package required}"
CODENAME="${3?codename required}"
ARCH="${4?arch required}"

if [ "$STATUS" != "success" ] && [ "$STATUS" != "failure" ]; then
  echo "Build status is '$STATUS', skipping issue management."
  exit 0
fi

TITLE="Build failure: ${PACKAGE} (${ARCH}/${CODENAME})"
LABEL="build-failure"
RUN_URL="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"

gh label create "$LABEL" --color "d73a4a" --description "Automated build failure" --force

ISSUE_NUMBER=$(gh issue list \
  --label "$LABEL" \
  --state open \
  --json number,title |
  jq -r --arg t "$TITLE" '.[] | select(.title == $t) | .number' | head -1)

if [ "$STATUS" = "failure" ]; then
  if [ -z "$ISSUE_NUMBER" ]; then
    gh issue create \
      --title "$TITLE" \
      --label "$LABEL" \
      --body "The **${PACKAGE}** build for \`${ARCH}/${CODENAME}\` failed.

[View workflow run](${RUN_URL})"
    echo "Opened issue: ${TITLE}"
  else
    echo "Issue #${ISSUE_NUMBER} already open for '${TITLE}', nothing to do."
  fi
else
  if [ -n "$ISSUE_NUMBER" ]; then
    gh issue comment "$ISSUE_NUMBER" \
      --body "Build succeeded — closing. [View run](${RUN_URL})"
    gh issue close "$ISSUE_NUMBER"
    echo "Closed issue #${ISSUE_NUMBER}: ${TITLE}"
  fi
fi
