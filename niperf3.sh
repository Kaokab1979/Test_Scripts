#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

# ===== Fixed ASML server details =====
SERVER_IP="172.29.192.139"
TCP_PORT="3003"
UDP_PORT="3002"   # ASML range 3000–3020; using 3020 for UDP

BASE_DIR="$HOME/ASML_Test"
mkdir -p "$BASE_DIR"

# Prefer Termux storage symlink; fallback to public path
DL_BASE="$HOME/storage/downloads"
[ -d "$DL_BASE" ] || DL_BASE="/sdcard/Download"

need_cmd() { command -v "$1" >/dev/null || { echo "[ERROR] Missing '$1'. Install it: pkg install $2"; exit 1; }; }

echo "------------------------------------------------------------"
echo " ASML iPerf3 Client (Fixed IP/Ports) for Termux"
echo " Server : $SERVER_IP"
echo " TCP    : $TCP_PORT"
echo " UDP    : $UDP_PORT"
echo " Logs   : $BASE_DIR  (+ copy to $DL_BASE/ASML_Test)"
echo "------------------------------------------------------------"

# ---- First-time storage permission hint ----
if [ ! -d "$HOME/storage" ] && [ ! -d "/sdcard/Download" ]; then
  echo "[NOTE] To enable saving to Downloads, run once: termux-setup-storage"
fi

# ---- Dependency checks ----
need_cmd iperf3 iperf3
need_cmd ping iputils
need_cmd timeout coreutils
need_cmd tee coreutils
need_cmd awk awk

check_port() { # test TCP control channel (iperf3 control)
  timeout 3 bash -c "echo > /dev/tcp/$1/$2" >/dev/null 2>&1
}

while :; do
  # --- Labels for this run ---
  read -rp "Enter device label (Getac/Zebra/Samsung/PNC560): " DEVICE_LABEL
  read -rp "Enter network label (WiFi/PrivateAPN): " NET_LABEL
  DEVICE_LABEL="${DEVICE_LABEL// /_}"
  NET_LABEL="${NET_LABEL// /_}"
  TS="$(date '+%Y-%m-%d_%H-%M-%S')"
  RUN_DIR="$BASE_DIR/${TS}_${DEVICE_LABEL}_${NET_LABEL}"
  mkdir -p "$RUN_DIR"

  echo
  echo "[CHECK] ping $SERVER_IP ..."
  if ! ping -c 3 -W 2 "$SERVER_IP" >/dev/null; then
    echo "[FAIL] Cannot ping $SERVER_IP. Check Wi-Fi/APN/VPN/firewall."
    read -rp "Retry run? (y/N): " R; [[ "${R,,}" == "y" ]] || break
    continue
  fi
  echo "[OK] Ping reachable."

  echo "[CHECK] TCP port $TCP_PORT on $SERVER_IP ..."
  if ! check_port "$SERVER_IP" "$TCP_PORT"; then
    echo "[FAIL] TCP $TCP_PORT not open on server. Ask to start:  iperf3 -s -p $TCP_PORT"
    read -rp "Retry run? (y/N): " R; [[ "${R,,}" == "y" ]] || break
    continue
  fi
  echo "[OK] TCP reachable."

  echo "[CHECK] UDP control (TCP) port $UDP_PORT on $SERVER_IP ..."
  if ! check_port "$SERVER_IP" "$UDP_PORT"; then
    echo "[WARN] UDP control not reachable on $UDP_PORT. Confirm server: iperf3 -s -p $UDP_PORT"
  else
    echo "[OK] UDP control reachable."
  fi

  echo
  echo "[STEP] Warm-up ping (5 packets)..."
  ping -c 5 "$SERVER_IP" > "$RUN_DIR/01_ping_warmup.txt"

  echo "[STEP] TCP forward (30s, 1s interval)..."
  iperf3 -c "$SERVER_IP" -p "$TCP_PORT" -i 1 -t 30 \
    | tee "$RUN_DIR/02_tcp_forward.txt"
  iperf3 -J -c "$SERVER_IP" -p "$TCP_PORT" -i 1 -t 30 \
    > "$RUN_DIR/02_tcp_forward.json" 2>/dev/null

  echo "[STEP] TCP reverse (30s, 1s interval)..."
  iperf3 -c "$SERVER_IP" -p "$TCP_PORT" -i 1 -t 30 -R \
    | tee "$RUN_DIR/03_tcp_reverse.txt"
  iperf3 -J -c "$SERVER_IP" -p "$TCP_PORT" -i 1 -t 30 -R \
    > "$RUN_DIR/03_tcp_reverse.json" 2>/dev/null

  echo "[STEP] UDP @50M (30s, 1s interval)..."
  iperf3 -c "$SERVER_IP" -u -p "$UDP_PORT" -b 50M -i 1 -t 30 \
    | tee "$RUN_DIR/04_udp_50M.txt"
  iperf3 -J -c "$SERVER_IP" -u -p "$UDP_PORT" -b 50M -i 1 -t 30 \
    > "$RUN_DIR/04_udp_50M.json" 2>/dev/null

  echo "[STEP] UDP @100M (30s, 1s interval)..."
  iperf3 -c "$SERVER_IP" -u -p "$UDP_PORT" -b 100M -i 1 -t 30 \
    | tee "$RUN_DIR/05_udp_100M.txt"
  iperf3 -J -c "$SERVER_IP" -u -p "$UDP_PORT" -b 100M -i 1 -t 30 \
    > "$RUN_DIR/05_udp_100M.json" 2>/dev/null

  echo "[STEP] Long ping (12 packets, 200ms interval)..."
  ping -c 12 -i 0.2 "$SERVER_IP" > "$RUN_DIR/06_ping_long.txt"

  # Copy to Downloads for easy pull
  DST="$DL_BASE/ASML_Test/${TS}_${DEVICE_LABEL}_${NET_LABEL}"
  mkdir -p "$DL_BASE/ASML_Test"
  cp -r "$RUN_DIR" "$DST" 2>/dev/null || true

  echo
  echo "DONE. Logs saved in: $RUN_DIR"
  echo "[OK] Also copied to: $DST"
  echo "Pull from Windows laptop with:"
  echo "  adb pull \"/sdcard/Download/ASML_Test\" C:\\Users\\fsleman\\Desktop\\ASML_Test"
  echo "Files:"
  printf "  %s\n" 01_ping_warmup.txt 02_tcp_forward.txt 03_tcp_reverse.txt 04_udp_50M.txt 05_udp_100M.txt 06_ping_long.txt

  echo
  read -rp "Run another test (y/N)? " AGAIN
  [[ "${AGAIN,,}" == "y" ]] || break
done

echo "Exiting. Stay awesome!"
