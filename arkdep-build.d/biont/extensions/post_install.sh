#! /usr/bin/env bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Function to execute a script and handle errors
execute_script() {
  local script_path="$1"
  echo "Executing script: $script_path"
  source "$script_path" || echo "Script failed: $script_path"
}

for f in $SCRIPT_DIR/post_install.d/*.sh; do
  execute_script "$f"
done
