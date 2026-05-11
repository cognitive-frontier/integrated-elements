#!/usr/bin/env bash
# deploy.sh — full one-shot deployment of a standalone GitHub Pages site.
#
# Usage:
#   ./deploy.sh <github-username-or-org> <repo-name> [commit-message]
#
# What it does (all from one command):
#   1. Pulls your GitHub PAT from the macOS Keychain (the one git already uses).
#   2. Creates the repo on GitHub via the API.
#   3. Initializes a local git repo, commits, pushes to main.
#   4. Enables GitHub Pages (source: main branch, root).
#
# Prereqs:
#   - You've previously authenticated `git push` to github.com on this Mac
#     (so a token is already in your Keychain under server `github.com`).
#   - That token has `repo` scope.
#   - The first run may show a one-time Keychain prompt asking permission
#     for `security` to read the github.com password — click "Always Allow".

set -euo pipefail

# ---- Arg parsing ----
if [ "$#" -lt 2 ]; then
  echo "Usage: ./deploy.sh <github-username> <repo-name> [commit-message]"
  echo "Example: ./deploy.sh cognitive-frontier integrated-elements"
  exit 1
fi

USERNAME="$1"
REPO="$2"
MSG="${3:-Initial site}"
REMOTE_URL="https://github.com/${USERNAME}/${REPO}.git"

# ---- Sanity checks ----
if ! command -v git >/dev/null 2>&1; then
  echo "Error: git is not installed."
  exit 1
fi

if [ ! -f "index.html" ]; then
  echo "Error: no index.html in the current directory. Run from the site folder."
  exit 1
fi

# ---- Pull token from Keychain ----
echo "→ Retrieving GitHub token from Keychain..."
TOKEN=$(security find-internet-password -s github.com -w 2>/dev/null || true)
if [ -z "$TOKEN" ]; then
  echo "Error: no github.com token found in Keychain."
  echo "Authenticate at least one git push to github.com first (any repo)."
  exit 1
fi

# ---- Determine if owner is the authed user or an org ----
AUTHED_USER=$(curl -sf -H "Authorization: token $TOKEN" https://api.github.com/user \
  | sed -n 's/.*"login": *"\([^"]*\)".*/\1/p' | head -1)

if [ -z "$AUTHED_USER" ]; then
  echo "Error: token in Keychain rejected by GitHub API. It may be revoked or expired."
  echo "Generate a fresh PAT, push to any repo to update Keychain, then re-run."
  exit 1
fi

if [ "$AUTHED_USER" = "$USERNAME" ]; then
  CREATE_ENDPOINT="https://api.github.com/user/repos"
else
  CREATE_ENDPOINT="https://api.github.com/orgs/${USERNAME}/repos"
fi

# ---- Create repo (idempotent) ----
echo "→ Creating repo ${USERNAME}/${REPO}..."
HTTP_CODE=$(curl -s -o /tmp/gh_create_resp -w "%{http_code}" \
  -X POST \
  -H "Authorization: token $TOKEN" \
  -H "Accept: application/vnd.github+json" \
  -d "{\"name\":\"${REPO}\",\"private\":false,\"auto_init\":false}" \
  "$CREATE_ENDPOINT")

case "$HTTP_CODE" in
  201) echo "  Created." ;;
  422) echo "  Repo already exists — continuing." ;;
  *)
    echo "Error: repo create returned HTTP $HTTP_CODE:"
    cat /tmp/gh_create_resp
    echo
    exit 1
    ;;
esac

# ---- Init local git (idempotent) ----
if [ ! -d ".git" ]; then
  echo "→ Initializing local git repo..."
  git init -q
  git branch -M main
fi

# ---- Stage + commit ----
echo "→ Staging files..."
git add .

if git diff --cached --quiet; then
  echo "→ Nothing new to commit."
else
  echo "→ Committing: \"$MSG\""
  git commit -q -m "$MSG"
fi

# ---- Remote setup ----
if git remote get-url origin >/dev/null 2>&1; then
  CURRENT=$(git remote get-url origin)
  if [ "$CURRENT" != "$REMOTE_URL" ]; then
    git remote set-url origin "$REMOTE_URL"
  fi
else
  git remote add origin "$REMOTE_URL"
fi

# ---- Push ----
echo "→ Pushing to main..."
git push -u origin main

# ---- Enable Pages (idempotent) ----
echo "→ Enabling GitHub Pages..."
PAGES_CODE=$(curl -s -o /tmp/gh_pages_resp -w "%{http_code}" \
  -X POST \
  -H "Authorization: token $TOKEN" \
  -H "Accept: application/vnd.github+json" \
  -d '{"source":{"branch":"main","path":"/"}}' \
  "https://api.github.com/repos/${USERNAME}/${REPO}/pages")

case "$PAGES_CODE" in
  201|202) echo "  Pages enabled." ;;
  409) echo "  Pages already enabled — continuing." ;;
  *)
    echo "  Note: Pages auto-enable returned HTTP $PAGES_CODE."
    echo "  Enable manually if needed: https://github.com/${USERNAME}/${REPO}/settings/pages"
    ;;
esac

# ---- Clean up temp files ----
rm -f /tmp/gh_create_resp /tmp/gh_pages_resp

echo
echo "✓ Done."
echo "  Live in ~1 minute at: https://${USERNAME}.github.io/${REPO}/"
