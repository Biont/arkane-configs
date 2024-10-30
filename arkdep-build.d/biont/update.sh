# Arkdep is pre EFI var drop version
if [[ -f $arkdep_boot/loader/entries/${data[0]}.conf ]]; then
	mv $arkdep_boot/loader/entries/${data[0]}.conf $arkdep_boot/loader/entries/$(date +%Y%m%d-%H%M%S)-${data[0]}+3.conf
	bootctl set-default ''
fi

if [[ -e /var/lib/fprint ]]; then
	cp -rT /var/lib/fprint $arkdep_dir/deployments/${data[0]}/var/lib/fprint
fi
