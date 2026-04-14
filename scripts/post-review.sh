#!/usr/bin/env bash
set -euo pipefail

REVIEW_FILE="/tmp/review.json"

if [ ! -f "$REVIEW_FILE" ]; then
  echo "No review file generated"
  exit 1
fi

if ! jq -e 'type == "array" and all(has("file") and has("line") and has("body"))' "$REVIEW_FILE" > /dev/null 2>&1; then
  echo "::error::Invalid review.json format — expected array of {file, line, body}"
  cat "$REVIEW_FILE"
  exit 1
fi

COMMENT_COUNT=$(jq length "$REVIEW_FILE")
echo "Posting ${COMMENT_COUNT} review comments..."

if [ "$COMMENT_COUNT" -eq 0 ]; then
  gh pr comment "$PR_NUMBER" --repo "$REPO" --body "🤖 **Claude Code Review** — No issues found. Looks good!"
  echo "Posted 'no issues' summary"
  exit 0
fi

# Separate general comments (file=null) from inline comments
GENERAL_COMMENTS=$(jq '[.[] | select(.file == null or .line == null)]' "$REVIEW_FILE")
INLINE_COMMENTS=$(jq '[.[] | select(.file != null and .line != null)]' "$REVIEW_FILE")

GENERAL_COUNT=$(echo "$GENERAL_COMMENTS" | jq length)
INLINE_COUNT=$(echo "$INLINE_COMMENTS" | jq length)

# Post general comments as PR comments
if [ "$GENERAL_COUNT" -gt 0 ]; then
  for i in $(seq 0 $((GENERAL_COUNT - 1))); do
    echo "$GENERAL_COMMENTS" | jq -r ".[$i].body" | gh pr comment "$PR_NUMBER" --repo "$REPO" --body-file -
    echo "General comment $((i + 1))/${GENERAL_COUNT}: posted"
    sleep 0.3
  done
fi

# Post inline comments as a single PR review (batch)
if [ "$INLINE_COUNT" -gt 0 ]; then
  # Build the comments array for the review API
  REVIEW_COMMENTS=$(echo "$INLINE_COMMENTS" | jq '[.[] | {
    path: .file,
    line: .line,
    side: "RIGHT",
    body: .body
  }]')

  # Combine all inline comments into one review body
  REVIEW_BODY="🤖 **Claude Code Review**"

  # Use GitHub API to create a review with all inline comments at once
  BATCH_OK=1
  jq -n \
    --arg commit_id "$HEAD_SHA" \
    --arg body "$REVIEW_BODY" \
    --argjson comments "$REVIEW_COMMENTS" \
    --arg event "COMMENT" \
    '{
      commit_id: $commit_id,
      body: $body,
      event: $event,
      comments: $comments
    }' | gh api \
      --method POST \
      -H "Accept: application/vnd.github+json" \
      "/repos/${REPO}/pulls/${PR_NUMBER}/reviews" \
      --input - 2>/tmp/review_error.txt || BATCH_OK=0

  if [ "$BATCH_OK" -eq 1 ]; then
    echo "Posted review with ${INLINE_COUNT} inline comments"
  else
    echo "Batch review failed, falling back to individual comments..."
    cat /tmp/review_error.txt
    for i in $(seq 0 $((INLINE_COUNT - 1))); do
      FILE=$(echo "$INLINE_COMMENTS" | jq -r ".[$i].file")
      LINE=$(echo "$INLINE_COMMENTS" | jq -r ".[$i].line")
      BODY=$(echo "$INLINE_COMMENTS" | jq -r ".[$i].body")
      FALLBACK="**\`${FILE}:${LINE}\`** — ${BODY}"
      echo "$FALLBACK" | gh pr comment "$PR_NUMBER" --repo "$REPO" --body-file -
      echo "Fallback comment $((i + 1))/${INLINE_COUNT}: posted"
      sleep 0.3
    done
  fi
fi
