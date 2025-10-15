#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

# --- storage (first run only) ---
[ -d "$HOME/storage" ] || termux-setup-storage

# ===== Fixed server/paths/ports =====
BASE_URL="http://172.29.192.139"
PORT="80"
FILE_100="testfile-100mb"
FILE_500="testfile-500mb"
FILE_1G="testfile-1gb"

# ===== Ask labels once =====
read -rp "Enter device name (e.g. Getac/Samsung/Zebra): " DEVICE_LABEL
read -rp "Enter network name (e.g. WiFi/PrivateAPN): " NET_LABEL
DEVICE_LABEL="${DEVICE_LABEL// /_}"
NET_LABEL="${NET_LABEL// /_}"

# ===== Check deps =====
for cmd in curl awk; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "[ERROR] Missing '$cmd'. Run: pkg update && pkg install curl awk"; exit 1; }
done

fetch_one() {
  friendly="$1"
  file_seg="$2"

  TS="$(date '+%Y-%m-%d_%H-%M-%S')"
  BASE="/sdcard/Download/HTTP_Test"
  OUTDIR="${BASE}/${TS}_${DEVICE_LABEL}_${NET_LABEL}"
  mkdir -p "$OUTDIR"

  URL="${BASE_URL}/${file_seg}"
  MET="${OUTDIR}/${file_seg}_metrics.txt"
  ERR="${OUTDIR}/${file_seg}_curl_errors.txt"
  HDR="${OUTDIR}/${file_seg}_head.txt"

  echo "[STEP] Downloading ${friendly} from ${URL} ... START"
  # HEAD
  curl -sSI "$URL" >"$HDR" 2>"$ERR" || echo "[WARN] HEAD failed, continuing..."

  # metrics only (no payload saved)
  curl -sS -H "Cache-Control: no-cache" -H "Pragma: no-cache" -o /dev/null -w "http_code=%{http_code}\nsize_download=%{size_download}\nspeed_download_Bps=%{speed_download}\ntime_namelookup=%{time_namelookup}\ntime_connect=%{time_connect}\ntime_starttransfer_TTFB=%{time_starttransfer}\ntime_total=%{time_total}\n" "$URL" >"$MET" 2>>"$ERR"

  {
    echo "Server=$BASE_URL"
    echo "Port=$PORT"
    echo "Path=/$file_seg"
    echo "Device=$DEVICE_LABEL"
    echo "Network=$NET_LABEL"
    echo "RunTag=${TS}_${DEVICE_LABEL}_${NET_LABEL}"
    echo "FileLabel=$friendly"
  } >>"$MET"

  awk -F= 'BEGIN { bps=0 } $1=="speed_download_Bps" { bps=$2+0 } END { mbps=(bps*8.0)/1000000.0; printf("speed_download_Mbps=%.3f\n", mbps) }' "$MET" >>"$MET"

  echo "[DONE] ${friendly} complete. Metrics: $MET"
  echo "[OUT ] Folder: $OUTDIR"
  echo
}

while true; do
  clear
  echo "------------------------------------------------------------"
  echo " ASML HTTP Download Test (Fixed)   Port: $PORT"
  echo " Server: $BASE_URL"
  echo " Files : /$FILE_100 , /$FILE_500 , /$FILE_1G"
  echo " Labels: Device=$DEVICE_LABEL  Network=$NET_LABEL"
  echo " Output: /sdcard/Download/HTTP_Test/<timestamp>_Device_Network"
  echo "------------------------------------------------------------"
  echo "1) Run ALL (100MB, 500MB, 1GB)"
  echo "2) Run 100MB only"
  echo "3) Run 500MB only"
  echo "4) Run 1GB only"
  echo "Q) Quit"
  read -rp "Select option: " opt

  case "${opt^^}" in
    1) fetch_one "100 MB" "$FILE_100"; fetch_one "500 MB" "$FILE_500"; fetch_one "1 GB" "$FILE_1G" ;;
    2) fetch_one "100 MB" "$FILE_100" ;;
    3) fetch_one "500 MB" "$FILE_500" ;;
    4) fetch_one "1 GB"   "$FILE_1G" ;;
    Q) echo "Bye."; exit 0 ;;
    *) echo "Invalid option."; sleep 1 ;;
  esac

  read -rp "Run again? [y/N]: " again
  [[ "${again,,}" == "y" ]] || { echo "Done."; break; }
done
