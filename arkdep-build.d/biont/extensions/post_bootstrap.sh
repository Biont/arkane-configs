SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

for f in $SCRIPT_DIR/post_bootstrap.d/*.sh; do source $f; done


