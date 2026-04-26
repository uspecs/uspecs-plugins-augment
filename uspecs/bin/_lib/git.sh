#!/usr/bin/env bash

# Well, we do not neeed it, since it is sourced, just for consistency with other scripts
set -Eeuo pipefail

# git.sh -- Git branch and pull request automation
#
# Provides reusable functions for the PR workflow: branch creation from a
# remote default branch, and PR submission via GitHub CLI.
# Intended to be sourced, not executed directly.
#
# Concepts:
#   pr_remote   The remote that owns the target branch for PRs.
#               "upstream" when a fork setup is detected, otherwise "origin".
#   change_branch  The current working branch (named {change-name}).
#   pr_branch      The squashed PR branch (named {change-name}--pr).



# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# shellcheck source=utils.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/utils.sh"

determine_pr_remote() {
    if git remote | grep -q '^upstream$'; then
        echo "upstream"
    else
        echo "origin"
    fi
}

gh_create_pr() {
    # Usage: printf '%s' "$body" | gh_create_pr <pr_remote> <default_branch> <head_branch> <title>
    # Creates a PR via GitHub CLI and outputs the PR URL. Reads body from stdin.
    local pr_remote="$1" default_branch="$2" head_branch="$3" title="$4"

    local pr_repo
    pr_repo="$(git remote get-url "$pr_remote" | sed -E 's#.*github.com[:/]##; s#\.git$##')"
    local pr_args=('--repo' "$pr_repo" '--base' "$default_branch" '--title' "$title" '--body-file' '-')

    if [[ "$pr_remote" == "upstream" ]]; then
        local origin_owner
        origin_owner="$(git remote get-url origin | sed -E 's#.*github.com[:/]##; s#\.git$##; s#/.*##')"
        gh pr create "${pr_args[@]}" --head "${origin_owner}:${head_branch}"
    else
        gh pr create "${pr_args[@]}" --head "$head_branch"
    fi
}

# git_validate_working_tree
# Reflects scenario: "Project inside Git working tree"
# Validates that the current directory is inside a git working tree.
git_validate_working_tree() {
    if ! is_git_repo "$PWD"; then
        error "No git repository found at $PWD"
    fi
}

# git_validate_clean_repo <current_branch> <default_branch>
# Reflects scenario: "Git working tree is clean"
# Validates: inside git working tree, no uncommitted changes, not on default branch.
git_validate_clean_repo() {
    local current_branch="$1"
    local default_branch="$2"

    git_validate_working_tree

    if [[ -n $(git status --porcelain) ]]; then
        error "Working directory has uncommitted changes. Commit or stash changes first"
    fi

    if [[ "$current_branch" == "$default_branch" ]]; then
        error "Current branch is the default branch '$default_branch'"
    fi
}

check_prerequisites() {
    # Check if git repository exists
    if ! is_git_repo "$PWD"; then
        error "No git repository found at $PWD"
    fi

    # Check if GitHub CLI is installed
    if ! command -v gh &> /dev/null; then
        error "GitHub CLI (gh) is not installed. Install from https://cli.github.com/"
    fi

    # Check if origin remote exists
    if ! git remote | grep -q '^origin$'; then
        error "'origin' remote does not exist"
    fi

    # Check if working directory is clean
    if [[ -n $(git status --porcelain) ]]; then
        error "Working directory has uncommitted changes. Commit or stash changes first"
    fi
}

git_default_branch_name() {
    # Fast path: if exactly one of main/master exists locally, use it (no network).
    local has_main=false has_master=false
    git show-ref --verify --quiet refs/heads/main && has_main=true
    git show-ref --verify --quiet refs/heads/master && has_master=true

    if [[ "$has_main" == true && "$has_master" == false ]]; then
        echo "main"; return 0
    fi
    if [[ "$has_master" == true && "$has_main" == false ]]; then
        echo "master"; return 0
    fi

    # Both or neither exist -- ask the remote.
    local branch
    branch=$(git ls-remote --symref origin HEAD | awk '/^ref:/ {sub(/refs\/heads\//, "", $2); print $2}') || {
        error "Cannot determine the default branch from remote"
    }
    if [[ -z "$branch" ]]; then
        error "Cannot determine the default branch from remote"
    fi
    echo "$branch"
}

# ---------------------------------------------------------------------------
# Public functions
# ---------------------------------------------------------------------------

# git_pr_info <map_nameref> [project_dir]
# Populates an associative array with PR remote info.
# Keys populated: pr_remote, default_branch
# project_dir: directory to run git commands from (defaults to $PWD)
# Returns non-zero if info cannot be determined.
git_pr_info() {
    local -n _git_pr_info_map="$1"
    # $2 (project_dir) accepted for compatibility but unused -- script runs from project root.
    local pr_remote default_branch
    pr_remote=$(determine_pr_remote) || return 1
    default_branch=$(git_default_branch_name) || return 1
    _git_pr_info_map["pr_remote"]="$pr_remote"
    _git_pr_info_map["default_branch"]="$default_branch"
}

# git_prbranch <name>
# Fetch pr_remote and create a local branch from its default branch.
git_prbranch() {
    local name="${1:-}"
    [[ -z "$name" ]] && error "Usage: git_prbranch <name>"

    local pr_remote default_branch
    pr_remote=$(determine_pr_remote)
    default_branch=$(git_default_branch_name)

    echo "Fetching $pr_remote/$default_branch..."
    git fetch "$pr_remote" "$default_branch" 2>&1

    echo "Creating branch: $name"
    git checkout -b "$name" "$pr_remote/$default_branch"
}

# git_ffdefault
# Fetch pr_remote/default_branch and fast-forward the local default branch to it.
# Switches to the default branch if not already on it, and leaves there after completion.
# Fail fast if any of the following conditions are true:
#     working directory is not clean
#     branches have diverged (fast-forward not possible)
git_ffdefault() {
    check_prerequisites

    local pr_remote default_branch
    pr_remote=$(determine_pr_remote)
    default_branch=$(git_default_branch_name)

    local current_branch
    current_branch=$(git symbolic-ref --short HEAD)

    if [[ "$current_branch" != "$default_branch" ]]; then
        echo "Switching to '$default_branch'..."
        git checkout "$default_branch"
    fi

    echo "Fetching $pr_remote/$default_branch..."
    git fetch "$pr_remote" "$default_branch" 2>&1

    echo "Fast-forwarding $default_branch..."
    if ! git merge --ff-only "$pr_remote/$default_branch" 2>&1; then
        error "Cannot fast-forward '$default_branch' to '$pr_remote/$default_branch'. The branches have diverged."
    fi
}

# git_pr --title <title> --body <body> --next-branch <branch> [--delete-branch]
# Literal \n sequences in --body are decoded to actual newlines.
# Stage all changes, commit, push to origin, and open a PR against
# pr_remote's default branch. Switch to --next-branch afterwards.
# If --delete-branch is set, delete the current branch after switching.
# If no changes exist, switch to --next-branch and exit cleanly.
git_pr() {
    local title="" body="" next_branch="" delete_branch=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --title)         title="$2";       shift 2 ;;
            --body)          body="$2";        shift 2 ;;
            --next-branch)   next_branch="$2"; shift 2 ;;
            --delete-branch) delete_branch=true; shift ;;
            *) error "Unknown flag: $1" ;;
        esac
    done
    [[ -z "$title" ]]       && error "--title is required"
    [[ -z "$body" ]]        && error "--body is required"
    [[ -z "$next_branch" ]] && error "--next-branch is required"

    # Decode literal \n sequences to actual newlines
    body="${body//\\n/$'\n'}"

    local default_branch branch_name
    default_branch=$(git_default_branch_name)
    branch_name=$(git symbolic-ref --short HEAD)

    if [[ "$delete_branch" == "true" && "$branch_name" == "$next_branch" ]]; then
        error "Cannot delete branch '$branch_name' because it is the same as --next-branch"
    fi

    # Nothing to commit -- switch to next branch and exit
    if [[ -z $(git status --porcelain) ]]; then
        echo "No changes to commit. Cleaning up..."
        git checkout "$next_branch"
        if [[ "$delete_branch" == "true" ]]; then
            git branch -d "$branch_name"
        fi
        echo "No updates were needed."
        return 0
    fi

    local pr_remote
    pr_remote=$(determine_pr_remote)

    echo "Committing changes..."
    git add -A
    git commit -m "$title"

    echo "Pushing branch to origin..."
    git push -u origin "$branch_name"

    echo "Creating pull request to $pr_remote..."
    local pr_url
    pr_url=$(printf '%s' "$body" | gh_create_pr "$pr_remote" "$default_branch" "$branch_name" "$title")
    echo "Pull request created successfully!"

    echo "Switching to $next_branch..."
    git checkout "$next_branch"
    if [[ "$delete_branch" == "true" ]]; then
        echo "Deleting local branch $branch_name..."
        git branch -d "$branch_name"
        echo "Deleting local reference to remote branch..."
        git branch -dr "origin/$branch_name"
    fi

    # Output PR info for caller to parse (to stderr so it doesn't interfere with normal output)
    echo "PR_URL=$pr_url" >&2
    echo "PR_BRANCH=$branch_name" >&2
    echo "PR_BASE=$default_branch" >&2
}

# git_diff <path>
# Output git diff of the given path between HEAD and pr_remote/default_branch.
git_diff() {
    local diff_path="${1:-}"
    [[ -z "$diff_path" ]] && error "Usage: git_diff <path>"

    local pr_remote default_branch
    pr_remote=$(determine_pr_remote)
    default_branch=$(git_default_branch_name)

    git fetch "$pr_remote" "$default_branch" >/dev/null 2>&1 || true
    git diff "$pr_remote/$default_branch" HEAD -- "$diff_path"
}

