#!/bin/bash -e

shippable_replace() {
  mkdir -p /tmp/shippable_replace
  for file in "$@"; do
    local path=$(dirname $file)
    if [ -d "$file" ]; then
      echo "shippable_replace is not supported for directories"
      return 82
    fi
    if [ "$path" != '.' ]; then
      mkdir -p /tmp/shippable_replace/$path
    fi
    envsubst < "$file" > "/tmp/shippable_replace/$file"
    mv "/tmp/shippable_replace/$file" "$file"
  done
}

<% _.each(obj.integrationScripts, function (integrationScript) { %>
<%= integrationScript %>
<% }); %>
<% _.each(obj.scripts, function (script) { %>
<%= script %>
<% }); %>
