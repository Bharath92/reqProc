Function exec_cmd([string]$cmd) {
  $cmd_uuid = [guid]::NewGuid().Guid
  $date_time = (Get-Date).ToUniversalTime()
  $cmd_start_timestamp = [System.Math]::Truncate((Get-Date -Date $date_time -UFormat %s))
  Write-Output "__SH__CMD__START__|{`"type`":`"cmd`",`"sequenceNumber`":`"$cmd_start_timestamp`",`"id`":`"$cmd_uuid`"}|$cmd"

  $cmd_status = 0
  $ErrorActionPreference = "Stop"

  Try
  {
    $global:LASTEXITCODE = 0;
    Invoke-Expression $cmd
    $ret = $LASTEXITCODE
    if ($ret -ne 0) {
      $cmd_status = $ret
    }
  }
  Catch
  {
    $cmd_status = 1
    Write-Output $_
  }
  Finally
  {
    $date_time = (Get-Date).ToUniversalTime()
    $cmd_end_timestamp = [System.Math]::Truncate((Get-Date -Date $date_time -UFormat %s))
    Write-Output ""
    Write-Output "__SH__CMD__END__|{`"type`":`"cmd`",`"sequenceNumber`":`"$cmd_end_timestamp`",`"id`":`"$cmd_uuid`",`"exitcode`":`"$cmd_status`"}|$cmd"
    exit $cmd_status
  }
}

# exec_exe executes an exe program and throws a powershell exception if it fails
# $ErrorActionPreference = "Stop" catches only cmdlet exceptions
# Hence exit status of exe programs need to be wrapped and thrown as exception
Function exec_exe([string]$cmd, [string]$error_msg) {
  $global:LASTEXITCODE = 0;
  Invoke-Expression $cmd
  $ret = $LASTEXITCODE
  if ($ret -ne 0) {
    if ($error_msg) {
      $msg = "$cmd exited with $ret `n$error_msg"
    } else {
      $msg = "$cmd exited with $ret"
    }
    throw $msg
  }
}

$PRIVATE_KEY = @'
<%=privateKey%>
'@
$PROJECT_CLONE_URL = @'
<%=projectUrl%>
'@
$PROJECT_CLONE_LOCATION = @'
<%=cloneLocation%>
'@
$COMMIT_SHA = @'
<%=commitSha%>
'@
$IS_PULL_REQUEST = <%= shaData.isPullRequest ? "$TRUE" : "$FALSE" %>
$IS_PULL_REQUEST_CLOSE = <%= shaData.isPullRequestClose ? "$TRUE" : "$FALSE" %>
$PULL_REQUEST_SOURCE_URL = @'
<%=shaData.pullRequestSourceUrl%>
'@
$PULL_REQUEST_BASE_BRANCH = @'
<%=shaData.pullRequestBaseBranch%>
'@
$PROJECT = @'
<%=name%>
'@
$SUBSCRIPTION_PRIVATE_KEY_PATH = @'
<%=subPrivateKeyPath%>
'@

Function add_project_key() {
  $ssh_dir = Join-Path "$global:HOME" ".ssh"
  $key_file_path = Join-Path "$ssh_dir" "id_rsa"

  if (Test-Path $key_file_path) {
    echo "----> Removing key: $key_file_path"
    Remove-Item -Force $key_file_path
  }
  [IO.File]::WriteAllLines($key_file_path, $PRIVATE_KEY)
  & $env:OPENSSH_FIX_USER_FILEPERMS

  echo "----> Adding project key to ssh agent"
  exec_exe "ssh-agent"
  exec_exe "ssh-add $key_file_path"
}

Function add_subscription_key() {
  $ssh_dir = Join-Path "$global:HOME" ".ssh"
  $key_file_path = Join-Path "$ssh_dir" "id_rsa"

  if (Test-Path $key_file_path) {
    echo "----> Removing key: $key_file_path"
    Remove-Item -Force $key_file_path
  }
  Copy-Item -Path $SUBSCRIPTION_PRIVATE_KEY_PATH -Destination $key_file_path
  & $env:OPENSSH_FIX_USER_FILEPERMS

  echo "----> Adding subscription key to ssh agent"
  exec_exe "ssh-agent"
  exec_exe "ssh-add $key_file_path"
}

Function git_sync() {
  add_project_key

  $temp_clone_path = Join-Path "$env:TEMP" "Shippable\gitRepo"

  if (Test-Path $temp_clone_path) {
    echo "----> Removing already existing gitRepo"
    Remove-Item -Recurse -Force $temp_clone_path
  }

  echo "----> Cloning $PROJECT_CLONE_URL"
  exec_exe "git clone $PROJECT_CLONE_URL $temp_clone_path" "Unable to clone the repository. If this is a private repository, please make sure that the repository still contains Shippable's deploy key. If the deploy key is not present in the repository, you can use the \"Reset Project\" button on the project settings page to restore it."

  echo "----> Pushing Directory $temp_clone_path"
  pushd $temp_clone_path

  $git_user = Invoke-Expression "git config --get user.name"
  if (-not $git_user) {
    echo "----> Setting git user name"
    exec_exe "git config user.name 'Shippable Build'"
  }

  $git_email = Invoke-Expression "git config --get user.email"
  if (-not $git_email) {
    echo "----> Setting git user email"
    exec_exe "git config user.email 'build@shippable.com'"
  }

  echo "----> Checking out commit SHA"
  if ($IS_PULL_REQUEST) {
    add_subscription_key

    if ([string]::Compare($PROJECT_CLONE_URL, $PULL_REQUEST_SOURCE_URL, $TRUE) -ne 0) {
      exec_exe "git remote add PR $PULL_REQUEST_SOURCE_URL"
      exec_exe "git fetch PR"
    }
    exec_exe "git reset --hard $COMMIT_SHA"
    exec_exe "git merge origin/$PULL_REQUEST_BASE_BRANCH"

    add_project_key
  } else {
    exec_exe "git checkout $COMMIT_SHA"
  }

  popd

  echo "----> Copying to $PROJECT_CLONE_LOCATION"
  Copy-Item "$temp_clone_path\*" -Destination $PROJECT_CLONE_LOCATION -Recurse -Force

  echo "----> Removing temporary data"
  Remove-Item -Recurse -Force $temp_clone_path
  exec_exe "ssh-add -D"
}

exec_cmd git_sync
