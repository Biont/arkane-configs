echo "syde-$(date +%Y-%m-%d)-$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 10 | head -n 1)"
