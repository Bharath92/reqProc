#!/bin/bash -e
exec_cmd() {
  cmd=$@
  cmd_uuid=$(cat /proc/sys/kernel/random/uuid)
  cmd_start_timestamp=`date +"%s"`
  echo "__SH__CMD__START__|{\"type\":\"cmd\",\"sequenceNumber\":\"$cmd_start_timestamp\",\"id\":\"$cmd_uuid\"}|$cmd"
  eval "$cmd"
  cmd_status=$?
  if [ "$2" ]; then
    echo $2;
  fi

  cmd_end_timestamp=`date +"%s"`
  # If cmd output has no newline at end, marker parsing
  # would break. Hence force a newline before the marker.
  echo ""
  echo "__SH__CMD__END__|{\"type\":\"cmd\",\"sequenceNumber\":\"$cmd_start_timestamp\",\"id\":\"$cmd_uuid\",\"exitcode\":\"$cmd_status\"}|$cmd"
  return $cmd_status
}

export PRIVATE_KEY="<%=privateKey%>"
export PROJECT_CLONE_URL="<%=projectUrl%>"
export PROJECT_CLONE_LOCATION="<%=cloneLocation%>"
export COMMIT_SHA="<%=commitSha%>"
export IS_PULL_REQUEST=<%=shaData.isPullRequest%>
export PULL_REQUEST="<%=shaData.pullRequestNumber%>"
export PULL_REQUEST_BASE_BRANCH="<%=shaData.pullRequestBaseBranch%>"

git_sync() {
  echo "$PRIVATE_KEY" > /tmp/key.pem

  chmod 600 /tmp/key.pem

  {
    shippable_retry ssh-agent bash -c "ssh-add /tmp/key.pem; git clone $PROJECT_CLONE_URL $PROJECT_CLONE_LOCATION"
  } || {
    ret=$?
    echo "Unable to clone the repository. If this is a private repository, please make sure that the repository still contains Shippable's deploy key. If the deploy key is not present in the repository, you can use the \"Reset Project\" button on the project settings page to restore it."
    return $ret
  }

  echo "----> Pushing Directory $PROJECT_CLONE_LOCATION"
  pushd $PROJECT_CLONE_LOCATION

  echo "----> Setting git user name"
  git config --get user.name || git config user.name 'Shippable Build'
  git config --get user.email || git config user.email 'build@shippable.com'

  echo "----> Checking out commit SHA"
  if [ "$IS_PULL_REQUEST" != false ]; then
    {
      shippable_retry ssh-agent bash -c "ssh-add /tmp/key.pem; git fetch origin pull/$PULL_REQUEST/head"
    } || {
      ret=$?
      echo "Unable to fetch the repository. If this is a private repository, please make sure that the repository still contains Shippable's deploy key. If the deploy key is not present in the repository, you can use the \"Reset Project\" button on the project settings page to restore it."
      return $ret
    }
    git checkout -f FETCH_HEAD
    git merge origin/$PULL_REQUEST_BASE_BRANCH
  else
    git checkout $COMMIT_SHA
  fi

  echo "----> Popping $PROJECT_CLONE_LOCATION"
  popd
}

exec_cmd git_sync
