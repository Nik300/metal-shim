# Trova la partizione EFI del disco su cui è installato macOS. Da includere con "source" (usa fail()).
# Imposta EFI_DEV (es. disk0s1). Forzabile: EFI_DEV=disk1s1 zsh install.sh
# Non usa il boot-path di OpenCore in NVRAM: avviando dalla chiavetta punterebbe alla EFI della chiavetta.
find_oc_efi() {
  if [[ -n ${EFI_DEV:-} ]]; then
    echo "EFI forzata: $EFI_DEV"
  else
    local store disk
    store=$(diskutil info / | awk -F': *' '/APFS Physical Store/{print $2}')
    [[ -n $store ]] || fail "non trovo il disco fisico di / (indica la EFI con EFI_DEV=diskXsY)"
    disk=$(diskutil info $store | awk -F': *' '/Part of Whole/{print $2}')
    EFI_DEV=$(diskutil list $disk | awk '$2 == "EFI" {print $NF; exit}')
    [[ -n $EFI_DEV ]] || fail "nessuna partizione EFI su $disk (indicala con EFI_DEV=diskXsY)"
    echo "EFI del disco di sistema ($disk): $EFI_DEV"
  fi
  [[ $(diskutil info $EFI_DEV 2>/dev/null) == *"Partition Type:"*EFI* ]] \
    || fail "$EFI_DEV non è una partizione EFI (indicala con EFI_DEV=diskXsY)"
}
