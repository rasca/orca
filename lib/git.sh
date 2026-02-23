#!/bin/bash
# git.sh — Git worktree management, file copy, env substitution

# Create a git worktree for a session
create_worktree() {
    local project_root="$1"
    local session_name="$2"
    local base_branch="$3"
    local worktree_path="$4"

    echo "Checking if branch is up to date..."
    cd "$project_root"

    # Fetch latest changes (skip if no remote)
    local has_remote=false
    if git remote get-url origin > /dev/null 2>&1; then
        has_remote=true
        git fetch origin "$base_branch" 2>/dev/null || true
    fi

    local local_rev remote_rev
    local_rev=$(git rev-parse "$base_branch" 2>/dev/null)
    remote_rev=$(git rev-parse "origin/$base_branch" 2>/dev/null || true)

    if [ "$has_remote" = true ] && [ "$local_rev" != "$remote_rev" ] && [ -n "$remote_rev" ]; then
        echo ""
        echo "Warning: Local $base_branch is not up to date with origin/$base_branch"
        echo "Local:  $(git log --oneline -1 "$base_branch")"
        echo "Remote: $(git log --oneline -1 "origin/$base_branch")"
        echo ""
        read -p "Pull latest changes? (y/n) [y]: " pull_choice
        pull_choice=${pull_choice:-y}

        if [ "$pull_choice" = "y" ] || [ "$pull_choice" = "Y" ]; then
            echo "Pulling latest changes..."
            git pull origin "$base_branch" || {
                echo "Error: Failed to pull. Resolve conflicts and try again." >&2
                return 1
            }
        else
            read -p "Continue with outdated branch? (y/n) [n]: " cont_choice
            cont_choice=${cont_choice:-n}
            if [ "$cont_choice" != "y" ] && [ "$cont_choice" != "Y" ]; then
                echo "Cancelled."
                return 1
            fi
        fi
    else
        echo "Branch is up to date"
    fi

    echo "Creating git worktree at $worktree_path..."
    git worktree add -b "$session_name" "$worktree_path" "$base_branch"
}

# Create worktree from a PR branch
create_worktree_from_pr() {
    local project_root="$1"
    local pr_number="$2"
    local worktree_path="$3"

    cd "$project_root"

    # Fetch PR metadata
    echo "Fetching PR #$pr_number metadata..."
    local pr_info
    pr_info=$(gh pr view "$pr_number" --json number,title,headRefName,author,url,state 2>/dev/null)

    if [ -z "$pr_info" ]; then
        echo "Error: Could not fetch PR #$pr_number" >&2
        return 1
    fi

    local pr_branch pr_title pr_author pr_url pr_state
    pr_branch=$(echo "$pr_info" | jq -r '.headRefName')
    pr_title=$(echo "$pr_info" | jq -r '.title')
    pr_author=$(echo "$pr_info" | jq -r '.author.login')
    pr_url=$(echo "$pr_info" | jq -r '.url')
    pr_state=$(echo "$pr_info" | jq -r '.state')

    if [ "$pr_state" != "OPEN" ]; then
        echo "Warning: PR #$pr_number is $pr_state"
        read -p "Continue anyway? (y/n) [n]: " cont_choice
        cont_choice=${cont_choice:-n}
        if [ "$cont_choice" != "y" ] && [ "$cont_choice" != "Y" ]; then
            echo "Cancelled."
            return 1
        fi
    fi

    echo "PR #$pr_number: $pr_title"
    echo "Author: $pr_author"
    echo "Branch: $pr_branch"

    # Fetch the PR branch
    echo "Fetching PR branch..."
    local current_branch
    current_branch=$(git branch --show-current)

    if ! git fetch origin "$pr_branch:$pr_branch" 2>/dev/null; then
        git fetch origin "pull/$pr_number/head:$pr_branch"
    fi

    # Create worktree using PR branch
    echo "Creating git worktree..."
    git worktree add "$worktree_path" "$pr_branch"

    # Set up tracking
    cd "$worktree_path"
    git branch --set-upstream-to="origin/$pr_branch" "$pr_branch" 2>/dev/null || true

    # Restore original branch in main repo
    cd "$project_root"
    git checkout "$current_branch" 2>/dev/null || true

    # Output PR metadata as JSON for session storage
    echo "PR_BRANCH=$pr_branch"
    echo "PR_TITLE=$pr_title"
    echo "PR_AUTHOR=$pr_author"
    echo "PR_URL=$pr_url"
    echo "PR_NUMBER=$pr_number"
}

# Copy setup files from main project to worktree
copy_setup_files() {
    local project_root="$1"
    local worktree_path="$2"
    local config_file="$3"

    local files
    files=$(get_setup_copy_files "$config_file")

    for file in $files; do
        if [ -n "$file" ] && [ "$file" != "null" ]; then
            local src="$project_root/$file"
            local dst="$worktree_path/$file"

            if [ -f "$src" ]; then
                local dst_dir
                dst_dir=$(dirname "$dst")
                mkdir -p "$dst_dir"
                echo "Copying $file..."
                cp "$src" "$dst"
            fi
        fi
    done
}

# Apply env substitutions to copied files
apply_env_substitutions() {
    local worktree_path="$1"
    local config_file="$2"
    shift 2
    # remaining args are port key=value pairs
    local port_vars=("$@")

    # Get list of files that have substitutions
    local sub_files
    sub_files=$(yq eval '.setup.env_substitutions | keys | .[]' "$config_file" 2>/dev/null) || true

    for target_file in $sub_files; do
        if [ -n "$target_file" ] && [ "$target_file" != "null" ]; then
            local full_path="$worktree_path/$target_file"
            if [ -f "$full_path" ]; then
                local subs
                subs=$(get_env_substitutions "$config_file" "$target_file")

                while IFS= read -r sub; do
                    if [ -n "$sub" ]; then
                        local key="${sub%%=*}"
                        local val="${sub#*=}"

                        # Interpolate port variables in the value
                        for pv in "${port_vars[@]}"; do
                            local pk="${pv%%=*}"
                            local pp="${pv#*=}"
                            val="${val//\$\{${pk}\}/$pp}"
                        done

                        # Apply substitution to file
                        if grep -q "^${key}=" "$full_path"; then
                            sed -i '' "s|^${key}=.*|${key}=${val}|" "$full_path"
                        else
                            echo "" >> "$full_path"
                            echo "${key}=${val}" >> "$full_path"
                        fi
                        echo "Set $key in $target_file"
                    fi
                done <<< "$subs"
            fi
        fi
    done
}

# Remove a worktree and its branch
remove_worktree() {
    local project_root="$1"
    local worktree_path="$2"
    local branch_name="$3"

    if [ -d "$worktree_path" ]; then
        echo "Removing git worktree..."
        cd "$project_root"
        git worktree remove "$worktree_path" --force 2>/dev/null || true

        # If directory still exists, remove manually
        if [ -d "$worktree_path" ]; then
            echo "Removing directory manually..."
            rm -rf "$worktree_path"
        fi
    fi

    # Remove branch
    if [ -n "$branch_name" ]; then
        cd "$project_root"
        if git show-ref --verify --quiet "refs/heads/$branch_name"; then
            echo "Removing git branch: $branch_name"
            git branch -D "$branch_name"
        fi
    fi
}
