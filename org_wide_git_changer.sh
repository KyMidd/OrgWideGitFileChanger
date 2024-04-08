#!/bin/bash

# Summary
# This tool is intended to loop over every repo within an Org or User space, and make changes to the repo.
# It's useful for when you need to make a change to every repo in an org

# Auth Requirements
# Make sure to export your github token. If SSO is enabled in your Org, you will need to authorize your token for SSO within the Org
# export GITHUB_TOKEN='ghp_xxxx'

# check to make sure GITHUB_TOKEN is set
if [ -z "$GITHUB_TOKEN" ]; then 
  echo '$GITHUB_TOKEN is not set, please set it and try again'
  exit 0
fi

# Set vars
gh_org=practicefusion # Your GitHub Organization (or your username, if that's where your repos are)

# PR information - please customize this information
pr_body="🤖 DO-6769 Update commitNotify and Jenkins_Any for new jenkins 🤖"
pr_title="🤖 DO-6769 Update commitNotify and Jenkins_Any for new jenkins 🤖"
branch_name="feature/DO-6769-Update-actions-for-jenkins-change"
commit_message="DO-6769 Update for new jenkins"

# Should we use admin privileges to merge PR. 
# If true, admin privileges will be used to merge the PR. You must have admin privileges to use this option. 
# If false, the PR will not be automatically merged. The URL will be written to the log, and you must merge them manually
auto_merge_pr=true

# Get the names of all repos in the org
# This method is limited to 1k repos, if you have more than 1k repos, use this method: https://medium.com/@kymidd/lets-do-devops-github-api-paginated-calls-more-than-1k-repos-3ff0cc92cc50
#org_repos=$(gh repo list --no-archived $gh_org -L 1000 --json name --jq '.[].name')
org_repos=$(cat all_repos)

# Hold until rate-limit success
hold_until_rate_limit_success() {
  
  # Loop forever
  while true; do
    
    # Any call to AWS returns rate limits in the response headers
    API_RATE_LIMIT_UNITS_REMAINING=$(curl -sv \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer $GITHUB_TOKEN" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      https://api.github.com/repos/$gh_org/ActionPRValidate_AnyJobRun/autolinks 2>&1 1>/dev/null \
      | grep -E '< x-ratelimit-remaining' \
      | cut -d ' ' -f 3 \
      | xargs \
      | tr -d '\r')

    # If API rate-limiting is hit, sleep for 1 minute
    # Rounded parenthesis are used to trigger arithmetic expansion, which compares more than the first numeric digit (bash is weird)
    if (( "$API_RATE_LIMIT_UNITS_REMAINING" < 100 )); then
      echo "ℹ️  We have less than 100 GitHub API rate-limit tokens left ($API_RATE_LIMIT_UNITS_REMAINING), sleeping for 1 minute"
      sleep 60
    
    # If API rate-limiting shows remaining units, break out of loop and function
    else  
      echo "💥  Rate limit checked, we have "$API_RATE_LIMIT_UNITS_REMAINING" core tokens remaining so we are continuing"
      break
    fi

  done
}

# Iterate over all repos, make changes
while IFS=$'\n' read -r gh_repo; do
  
  # Check rate limit blockers, hold if token bucket too low
  hold_until_rate_limit_success
  
  # Clone the repo, will fail if the repo folder already exists
  git clone git@github.com:$gh_org/${gh_repo}.git

  # Change directories into the repo
  cd "$gh_repo"

  ###
  ### Make your changes here
  ### Add or delete any files you need to this location
  ### For example, modify any file, or copy over existing files
  ###
  cp /Users/kyler/git/GitHub/KyMidd/OrgWideGitFileChanger/src/MergeCommitNotify.yml .github/workflows/MergeCommitNotify.yml
  cp /Users/kyler/git/GitHub/KyMidd/OrgWideGitFileChanger/src/ActionPRValidate_AnyJobRun.yaml .github/workflows/ActionPRValidate_AnyJobRun.yaml

  # Read the REST info on the repo to get the repo's default branch
  # Set that default branch as the base branch for the PR
  base_branch=$(curl -s \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    https://api.github.com/repos/$gh_org/$gh_repo | jq -r '.default_branch')
  
  # Git add with '.' target identifies all changes
  # Using the '-vvv' verbose flag to get the output of the git add command, which we will use to determine if there are changes
  git_add=$(git add -vvv .)
  
  # If there are no changes, the PR will not be created
  # Note that even modified files will show up as 'add' in the git add output
  if [[ $(echo "$git_add" | grep -E 'add|remove') ]]; then
    
    # Changes were made, checkout a branch and make a PR
    git checkout -b "$branch_name"
    git commit -m "$commit_message"
    git push origin "$branch_name"
    created_pr_url=$(gh pr create -b "$pr_body" -t "$pr_title" -B "$base_branch" --fill)

    # If auto_merge_pr is true, merge the PR
    if [ "$auto_merge_pr" = true ]; then
      gh pr merge --admin -d -m $created_pr_url
    else
      echo "PR created, please merge: $created_pr_url"
    fi

    # Sleep 2 seconds to avoid rate limiting
    sleep 2

  fi

  # Reset location
  cd ..

  # Cleanup repo
  rm -rf "$gh_repo"

done <<< "$org_repos"

# Finish
echo ""
echo "################"
echo "Done!"
echo "################"
exit 0