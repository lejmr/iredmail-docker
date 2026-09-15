#!/bin/bash
# Land a validated integration branch on master as a series of topical,
# squash-merged pull requests whose combined result is byte-identical to
# what was validated.
#
# Why not rebase: the integration branch is what the maintainer clicked
# through. Replaying its commits one topic at a time means conflict
# resolution, and every resolution is a chance to ship something nobody
# tested. So each PR is instead ONE commit on top of the current master
# whose TREE is a snapshot of the integration history at that topic's
# boundary. Squash-merging it makes master's tree exactly that snapshot;
# this script checks that after every merge and stops on the first mismatch.
# The last stage's tree is the validated tree, so master ends up identical.
#
# Usage: bin/merge-stages.sh <stages-file> <bodies-dir>
#
# stages-file: one stage per line, oldest first, fields separated by '|':
#   branch|source|pr|title|bodyfile
#   branch   - head branch to (re)write and push (must not be checked out
#              in any worktree - `git worktree list`)
#   source   - a commit (its tree is taken), a tree id, or `keep` to merge
#              the branch as it is (only for a branch already based on master)
#   pr       - existing PR number to retarget/retitle, or `new`
#   title    - PR title and squash subject; `fixes #N, fixes #M` closes
#              issues (GitHub needs the keyword before EVERY number)
#   bodyfile - file under <bodies-dir> with the PR body
# `#PR_<branch-slug>` in a body is replaced by the number of an earlier
# stage's PR (slug = branch with '/' -> '-').
#
# Needs: gh authenticated with push+merge rights, CI on pull_request.
# Stops on: push failure, PR create/edit failure, a failing check, merge
# failure, tree mismatch. Safe to re-run from the failed stage with a
# stages file that starts there (an already-open PR: pass its number).
set -u
STAGES_FILE=${1:?stages file}; BODIES=${2:?bodies dir}
TR=${MERGE_TRAILERS:-}
LOG=${MERGE_LOG:-merge-prs.txt}
: > "$LOG"
grep -v '^\s*$' "$STAGES_FILE" | grep -v '^\s*#' | while IFS='|' read -r branch src pr title bodyfile; do
  echo "=================== $(date +%H:%M:%S) stage $branch (src=$src pr=$pr)"
  git fetch -q origin master || exit 1
  base=$(git rev-parse origin/master)
  body=$(cat "$BODIES/$bodyfile")
  while read -r b n; do body=${body//"#PR_${b//\//-}"/"#$n"}; done < "$LOG"
  if [ "$src" = keep ]; then
    tree=$(git rev-parse "$branch^{tree}")
    git merge-base --is-ancestor "$base" "$branch" || { echo "FAIL $branch not based on master"; exit 1; }
  else
    if [ "$(git cat-file -t "$src")" = tree ]; then
      tree=$src
      echo "WARNING: $src is a bare tree - cannot verify it contains origin/master; make sure it was built on top of it"
    else
      # A snapshot from a branch that predates other merged PRs carries a tree
      # WITHOUT their changes, and the squash silently reverts them - the tree
      # check below cannot catch that (the tree is exactly the stale one).
      git merge-base --is-ancestor "$base" "$src" || { echo "FAIL $src does not contain origin/master ($base) - merge master into the topic branch, re-test, then snapshot"; exit 1; }
      tree=$(git rev-parse "$src^{tree}")
    fi
    commit=$(printf '%s\n\n%s\n' "$title" "$TR" | git commit-tree "$tree" -p "$base") || exit 1
    git branch -f "$branch" "$commit" || { echo "FAIL cannot move $branch (checked out somewhere?)"; exit 1; }
    git push -q -f origin "$branch" || { echo "FAIL push $branch"; exit 1; }
  fi
  if [ "$pr" = new ]; then
    url=$(gh pr create --base master --head "$branch" --title "$title" --body "$body") || { echo "FAIL pr create"; exit 1; }
    pr=${url##*/}
  else
    gh pr edit "$pr" --base master --title "$title" --body "$body" >/dev/null || { echo "FAIL pr edit $pr"; exit 1; }
  fi
  echo "$branch $pr" >> "$LOG"
  echo "PR #$pr ready, waiting for checks"
  sleep 30
  for i in $(seq 1 60); do
    out=$(gh pr checks "$pr" 2>&1)
    if echo "$out" | grep -qi "no checks"; then sleep 15; continue; fi
    if echo "$out" | grep -qE "pending|queued|in_progress"; then sleep 15; continue; fi
    break
  done
  echo "$out" | sed 's/^/   /'
  if echo "$out" | grep -qE "	fail"; then echo "FAIL checks on #$pr"; exit 1; fi
  echo "$out" | grep -q "pass" || { echo "FAIL no passing checks on #$pr"; exit 1; }
  gh pr merge "$pr" --squash --subject "$title" --body "$(printf '%s\n\n%s' "$body" "$TR")" || { echo "FAIL merge #$pr"; exit 1; }
  sleep 5; git fetch -q origin master
  got=$(git rev-parse "origin/master^{tree}")
  [ "$got" = "$tree" ] || { echo "FAIL tree mismatch after #$pr: master=$got expected=$tree"; exit 1; }
  echo "OK #$pr merged, master tree matches ($(git rev-parse --short origin/master))"
done
echo "=================== $(date +%H:%M:%S) DONE"
