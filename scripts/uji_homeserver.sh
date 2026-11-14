#!/usr/bin/env bash
# =============================================================================
# uji_homeserver.sh
# Skrip pengujian kinerja dan energi untuk penelitian:
# "Model Transformasi Komputer Lama menjadi Home Server Edukasi Berbasis
#  Open-Source yang Hemat Energi" (Penelitian Dasar, Universitas Tidar, 2026)
#
# Perangkat uji : HP ProDesk 405 G4 (Ryzen 5 PRO 2400GE), Intel NUC5CPYH
#                 (Celeron N3050), STB ZTE B860H V2A (Amlogic S905X)
# Skenario      : S0 idle, S1 konten statis, S2 konten dinamis, S3 CPU
#                 sintetis, S4 jaringan (sesuai Tabel 4 laporan)
#
# MODE                                           DIJALANKAN DI
#   info   <perangkat>                           perangkat uji
#   cpu    <perangkat>                           perangkat uji
#   klien  <perangkat> <url_statis> <url_dinamis> [ssh_target]
#                                                laptop klien (Linux/WSL2/macOS)
#   daya   <perangkat> <idle|sedang|tinggi> [durasi_detik]
#                                                laptop klien (pencatat watt)
#   beban  sedang <url_dinamis> [durasi_detik]   laptop klien
#   beban  tinggi [durasi_detik]                 perangkat uji
#   ringkas                                      laptop klien (setelah semua data
#                                                terkumpul dalam satu folder)
#
# Nama perangkat yang disarankan (dipakai konsisten di semua mode):
#   ryzen   intel   arm
#
# Variabel yang dapat diubah (contoh: DURASI=30 ./uji_homeserver.sh klien ...):
#   HASIL_DIR=./hasil_uji   KONEKSI="10 25 50 100"   ULANGAN=3   DURASI=60
#   JEDA=30   IDLE_DETIK=300   WIN_DETIK=60   CPU_DETIK=30   IPERF_DETIK=30   IPERF_HOST=
#   INTERVAL_DAYA=10   KONEKSI_SEDANG=25   BATAS_P99_MS=1000   BATAS_GALAT=1
#   PEMANASAN=0   (detik; mis. PEMANASAN=30 menjalankan beban 30 detik tanpa dicatat
#                  sebelum tiap skenario pada mode klien. Pakai nilai yang sama di ketiga perangkat.)
#   VIDEO=0   (VIDEO=1 pada mode daya: tanpa mengetik; bip + jam tiap interval sebagai
#              penanda rekaman video wattmeter; waktu dicatat di daya_video.csv)
#   TARIF=   (Rp/kWh, untuk estimasi biaya tahunan pada mode ringkas)
#
# Paket yang diperlukan:
#   perangkat uji : sysbench, procps (vmstat), iperf3, iw -> sudo apt install sysbench iperf3 iw
#                   (di WSL tidak perlu iw)
#   laptop klien  : wrk, iperf3, openssh-client         -> sudo apt install wrk iperf3
#
# PERANGKAT UJI DI WINDOWS + WSL2 (mini PC Ryzen)
#   Skrip mendeteksi WSL secara otomatis. Di WSL, data Wi-Fi dibaca dari Windows
#   (netsh wlan show interfaces), status hemat daya Wi-Fi dari powercfg, dan
#   utilisasi CPU Windows dicatat pada mode info SESUDAH jendela idle (kolom
#   cpu_windows_pct), agar pengukurnya tidak membebani pengukuran idle Ubuntu.
#   Sinyal Windows berupa persen; bila Windows tidak menampilkan RSSI, dBm
#   diperkirakan dengan rumus dBm = persen/2 - 100 (kolom sumber_sinyal).
#   Matikan hemat daya Wi-Fi Windows (PowerShell Administrator):
#   powercfg /setacvalueindex SCHEME_CURRENT 19cbb8fa-5279-450e-9fac-8a3d5fedd0c1 12bbebe6-58d6-4636-95bb-3217ef867c1a 0
#   powercfg /setactive SCHEME_CURRENT
#
# URUTAN PENGUJIAN (ulangi untuk ryzen, intel, arm; sekitar 1,5 jam per perangkat)
#   Klien dan perangkat uji tersambung Wi-Fi ke access point, SSID, dan pita yang
#   sama, dengan posisi dan jarak tetap. Setelah reboot, matikan hemat daya Wi-Fi:
#   sudo iw dev wlan0 set power_save off   (nama antarmuka: lihat 'iw dev')
#   Aplikasi uji (folder paket_uji): http://IP:8080/ (statis), http://IP:8080/uji.php (dinamis)
#   1. Perangkat uji : ./uji_homeserver.sh info arm          (S0 idle, 5 menit)
#   2. Perangkat uji : ./uji_homeserver.sh cpu arm           (S3)
#   3. Perangkat uji : iperf3 -s                             (biarkan berjalan)
#   4. Laptop klien  : ./uji_homeserver.sh klien arm http://IP:8080/ http://IP:8080/uji.php user@IP
#   5. Daya idle     : laptop  -> ./uji_homeserver.sh daya arm idle 300
#   6. Daya sedang   : laptop terminal A -> ./uji_homeserver.sh daya arm sedang 300
#                      laptop terminal B -> ./uji_homeserver.sh beban sedang http://IP:8080/uji.php 330
#   7. Daya tinggi   : laptop  -> ./uji_homeserver.sh daya arm tinggi 300
#                      perangkat uji -> ./uji_homeserver.sh beban tinggi 330
#   8. Laptop klien  : TARIF=<Rp/kWh> ./uji_homeserver.sh ringkas
#   idle.csv, cpu.csv, wifi.csv, dan info_<perangkat>.txt tersimpan di perangkat
#   uji; angka di dalamnya langsung mengisi Tabel 6, 7, dan 9 laporan.
#   beban.csv, daya.csv, dan hasil ringkas di laptop mengisi Tabel 10-13.
#   Halaman dinamis = halaman aplikasi praktikum yang membaca basis data.
# =============================================================================

set -u

HASIL_DIR="${HASIL_DIR:-./hasil_uji}"
KONEKSI="${KONEKSI:-10 25 50 100}"
ULANGAN="${ULANGAN:-3}"
DURASI="${DURASI:-60}"
JEDA="${JEDA:-30}"
IDLE_DETIK="${IDLE_DETIK:-300}"
WIN_DETIK="${WIN_DETIK:-60}"
CPU_DETIK="${CPU_DETIK:-30}"
IPERF_DETIK="${IPERF_DETIK:-30}"
IPERF_HOST="${IPERF_HOST:-}"
INTERVAL_DAYA="${INTERVAL_DAYA:-10}"
KONEKSI_SEDANG="${KONEKSI_SEDANG:-25}"
PEMANASAN="${PEMANASAN:-0}"
VIDEO="${VIDEO:-0}"
BATAS_P99_MS="${BATAS_P99_MS:-1000}"
BATAS_GALAT="${BATAS_GALAT:-1}"
TARIF="${TARIF:-}"

mkdir -p "$HASIL_DIR"

# ----------------------------------------------------------------- utilitas --
pesan() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
gagal() { printf 'GALAT: %s\n' "$*" >&2; exit 1; }
perlu() { command -v "$1" >/dev/null 2>&1 || gagal "perintah '$1' belum terpasang. $2"; }
bersih() { local s="${1//,/_}"; printf '%s' "${s// /_}"; }

tulis_csv() {
  # tulis_csv <berkas> <header> <baris>
  [ -f "$1" ] || printf '%s\n' "$2" > "$1"
  printf '%s\n' "$3" >> "$1"
}

suhu_maks() {
  # Suhu tertinggi (derajat C) dari thermal_zone atau hwmon; "NA" bila tidak ada.
  local f v maks=""
  for f in /sys/class/thermal/thermal_zone*/temp /sys/class/hwmon/hwmon*/temp*_input; do
    [ -r "$f" ] || continue
    v=$(cat "$f" 2>/dev/null) || continue
    [[ "$v" =~ ^[0-9]+$ ]] || continue
    if [ -z "$maks" ] || [ "$v" -gt "$maks" ]; then maks="$v"; fi
  done
  if [ -n "$maks" ]; then awk -v t="$maks" 'BEGIN{printf "%.1f", t/1000}'; else printf 'NA'; fi
}

rincian_vmstat() {
  # Rata-rata kolom us, sy, wa, st dari keluaran "vmstat 1 N" (stdin); sampel pertama dilewati.
  awk '!("id" in c) && $1=="r" {for(i=1;i<=NF;i++) c[$i]=i; next}
       ("id" in c) && $1 ~ /^[0-9]+$/ { d++; if (d > 1) {u+=$c["us"]; s+=$c["sy"]; w+=$c["wa"]; if ("st" in c) t+=$c["st"]; n++} }
       END{ if(n>0) printf "us %.1f, sy %.1f, wa %.1f, st %.1f", u/n, s/n, w/n, t/n; else printf "NA" }'
}

cpu_sibuk_dari_vmstat() {
  # Rata-rata utilisasi CPU (100 - id) dari keluaran "vmstat 1 N" pada stdin.
  # Hanya baris data (diawali angka) yang dihitung, sehingga judul kolom yang dicetak
  # ulang oleh vmstat tidak ikut terhitung. Sampel pertama (rata-rata sejak boot) dilewati.
  awk '!c && $1=="r" {for(i=1;i<=NF;i++) if($i=="id") c=i; next}
       c && $1 ~ /^[0-9]+$/ { d++; if (d > 1) {s+=$c; n++} }
       END{ if(n>0) printf "%.1f", 100 - s/n; else printf "NA" }'
}

# ------------------------------------------------- Windows + WSL2 (Ryzen) --
di_wsl() {
  [ -n "${WSL_DISTRO_NAME:-}" ] && return 0
  grep -qiE 'microsoft|wsl' /proc/sys/kernel/osrelease 2>/dev/null
}

winexe() {
  # winexe <program.exe> [argumen...] : menjalankan program Windows dari WSL
  local e="$1" p; shift
  for p in "$(command -v "$e" 2>/dev/null)" "/mnt/c/Windows/System32/$e" \
           "/mnt/c/Windows/System32/WindowsPowerShell/v1.0/$e"; do
    if [ -n "$p" ] && [ -x "$p" ]; then
      ( cd /mnt/c 2>/dev/null || true; "$p" "$@" )
      return
    fi
  done
  return 127
}

ps_win() {
  # ps_win <skrip PowerShell> : dijalankan lewat -EncodedCommand agar aman dari masalah tanda kutip
  local enc
  enc=$(printf '%s' "$1" | iconv -f UTF-8 -t UTF-16LE 2>/dev/null | base64 -w0) || return 1
  winexe powershell.exe -NoProfile -NonInteractive -EncodedCommand "$enc" 2>/dev/null | tr -d '\r'
}

wifi_windows() { winexe netsh.exe wlan show interfaces 2>/dev/null | tr -d '\r'; }

hemat_daya_windows() {
  # Power Saving Mode adaptor nirkabel (AC): 0 = Maximum Performance -> "off"
  local v
  v=$(winexe powercfg.exe /query SCHEME_CURRENT 19cbb8fa-5279-450e-9fac-8a3d5fedd0c1 \
        12bbebe6-58d6-4636-95bb-3217ef867c1a 2>/dev/null | tr -d '\r' \
      | grep -oiE '0x[0-9a-f]{8}' | head -n 1)
  if [ -z "$v" ]; then printf 'NA'; return; fi
  v=$((v))
  if [ "$v" -eq 0 ]; then printf 'off'; else printf 'on(%s)' "$v"; fi
}

nilai_netsh() {
  # nilai_netsh <regex_kunci> : nilai pertama dari "kunci : nilai" pada keluaran netsh (stdin)
  awk -F' : ' -v r="$1" '{
      k = $1; gsub(/^[ \t]+|[ \t]+$/, "", k)
      if (tolower(k) ~ r) { v = substr($0, index($0, " : ") + 3); gsub(/^[ \t]+|[ \t]+$/, "", v); print v; exit }
    }'
}

catat_wifi_wsl() {
  local dev="$1" raw ssid kanal pita freq pct rssi sinyal sumber laju ps
  raw=$(wifi_windows)
  if [ -z "$raw" ]; then pesan "Data Wi-Fi Windows tidak terbaca (netsh); wifi.csv tidak dibuat."; return; fi
  printf '== %s\n%s\n\n' "$(date -Iseconds)" "$raw" >> "$HASIL_DIR/wifi_windows_${dev}.txt"
  ssid=$(printf '%s\n' "$raw" | nilai_netsh '^ssid$')
  kanal=$(printf '%s\n' "$raw" | nilai_netsh '^(channel|saluran|kanal)$' | grep -oE '^[0-9]+')
  pita=$(printf '%s\n' "$raw" | nilai_netsh '^(band|pita)')
  laju=$(printf '%s\n' "$raw" | nilai_netsh '(transmit|kirim|transmisi)' | grep -oE '^[0-9]+([.,][0-9]+)?' | tr ',' '.')
  rssi=$(printf '%s\n' "$raw" | nilai_netsh '^rssi$' | grep -oE '^-[0-9]+')
  pct=$(printf '%s\n' "$raw" | awk -F' : ' '$2 ~ /^[ ]*[0-9]+[ ]*%[ ]*$/ {gsub(/[ %]/, "", $2); print $2; exit}')
  if [ -n "$rssi" ]; then sinyal="$rssi"; sumber="windows_rssi"
  elif [ -n "$pct" ]; then sinyal=$(awk -v p="$pct" 'BEGIN{printf "%.0f", p/2 - 100}'); sumber="windows_persen_${pct}"
  else sinyal="NA"; sumber="NA"; fi
  freq=$(awk -v c="${kanal:-}" -v b="${pita:-}" 'BEGIN{
      if (c == "") { print "NA"; exit }
      if (b ~ /6/)  { print 5950 + 5*c; exit }
      if (c == 14)  { print 2484; exit }
      if (c <= 14)  { print 2407 + 5*c; exit }
      print 5000 + 5*c }')
  ps=$(hemat_daya_windows)
  tulis_csv "$HASIL_DIR/wifi.csv" "perangkat,antarmuka,ssid,frekuensi_mhz,sinyal_dbm,laju_tx_mbit,hemat_daya,sumber_sinyal" \
    "$dev,windows,$(bersih "${ssid:-NA}"),${freq:-NA},${sinyal},${laju:-NA},${ps},${sumber}"
  pesan "Wi-Fi (Windows): SSID ${ssid:-NA}, ${freq:-NA} MHz, sinyal ${sinyal} dBm (${sumber}), laju ${laju:-NA} Mbit/s, hemat daya ${ps}"
  if [ "${ps%%(*}" = "on" ]; then
    pesan "  PERINGATAN: hemat daya Wi-Fi Windows masih aktif. Di PowerShell (Administrator):"
    pesan "  powercfg /setacvalueindex SCHEME_CURRENT 19cbb8fa-5279-450e-9fac-8a3d5fedd0c1 12bbebe6-58d6-4636-95bb-3217ef867c1a 0"
    pesan "  powercfg /setactive SCHEME_CURRENT"
  fi
}

cpu_windows() {
  # cpu_windows <detik> <berkas> : rata-rata % CPU Windows selama <detik> (sampel
  # tiap +-2 detik, sampel pertama dibuang) ditulis ke <berkas>.
  local skrip
  skrip=$(cat <<'PS'
$s = @()
$sw = [Diagnostics.Stopwatch]::StartNew()
while ($sw.Elapsed.TotalSeconds -lt __N__) {
  Start-Sleep -Seconds 2
  $s += (Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'").PercentProcessorTime
}
if ($s.Count -gt 1) {
  $r = ($s | Select-Object -Skip 1 | Measure-Object -Average).Average
  [string]::Format([Globalization.CultureInfo]::InvariantCulture, "{0:0.0}", $r)
}
PS
)
  skrip=${skrip//__N__/$1}
  ps_win "$skrip" > "$2"
}

antarmuka_wifi() {
  if command -v iw >/dev/null 2>&1; then
    iw dev 2>/dev/null | awk '$1=="Interface"{print $2}'
  else
    awk 'NR>2{sub(":","",$1); print $1}' /proc/net/wireless 2>/dev/null
  fi
}

catat_wifi() {
  # catat_wifi <perangkat> : SSID, frekuensi, sinyal, laju tautan, hemat daya -> wifi.csv
  if di_wsl; then catat_wifi_wsl "$1"; return; fi
  local dev="$1" ifc ssid freq sinyal laju ps sumber ada=0
  for ifc in $(antarmuka_wifi); do
    ada=1
    if command -v iw >/dev/null 2>&1; then
      sumber="iw"
      local link; link=$(iw dev "$ifc" link 2>/dev/null)
      ssid=$(printf '%s\n' "$link" | awk -F': ' '/SSID:/{print $2; exit}')
      freq=$(printf '%s\n' "$link" | awk '/freq:/{print $2; exit}')
      sinyal=$(printf '%s\n' "$link" | awk '/signal:/{print $2; exit}')
      laju=$(printf '%s\n' "$link" | awk '/tx bitrate:/{print $3; exit}')
      ps=$(iw dev "$ifc" get power_save 2>/dev/null | awk -F': ' '{print $2}')
    else
      ssid=""; freq=""; laju=""; ps=""; sumber="proc_net_wireless"
      sinyal=$(awk -v i="$ifc:" '$1==i{gsub(/\./,"",$4); print $4}' /proc/net/wireless)
    fi
    tulis_csv "$HASIL_DIR/wifi.csv" "perangkat,antarmuka,ssid,frekuensi_mhz,sinyal_dbm,laju_tx_mbit,hemat_daya,sumber_sinyal" \
      "$dev,$ifc,$(bersih "${ssid:-NA}"),${freq:-NA},${sinyal:-NA},${laju:-NA},${ps:-NA},${sumber}"
    pesan "Wi-Fi $ifc: SSID ${ssid:-NA}, ${freq:-NA} MHz, sinyal ${sinyal:-NA} dBm, laju ${laju:-NA} Mbit/s, hemat daya ${ps:-NA}"
    if [ "${ps:-}" = "on" ]; then pesan "  PERINGATAN: hemat daya Wi-Fi masih aktif. Jalankan: sudo iw dev $ifc set power_save off"; fi
  done
  [ "$ada" -eq 1 ] || pesan "Tidak ada antarmuka Wi-Fi terdeteksi; wifi.csv tidak dibuat."
}

# --------------------------------------------------------------- mode info --
mode_info() {
  [ $# -ge 1 ] || gagal "pemakaian: $0 info <perangkat>"
  local dev; dev=$(bersih "$1")
  perlu vmstat "Pasang paket procps."
  local berkas="$HASIL_DIR/info_${dev}.txt"

  pesan "Mencatat spesifikasi dan konfigurasi ke $berkas"
  {
    echo "== Waktu";        date -Iseconds
    echo "== Perangkat";    echo "$dev"
    echo "== uname -a";     uname -a
    echo "== os-release";   cat /etc/os-release 2>/dev/null
    echo "== lscpu";        lscpu 2>/dev/null
    echo "== free -m";      free -m
    echo "== lsblk";        lsblk -o NAME,SIZE,TYPE,ROTA,MODEL,MOUNTPOINT 2>/dev/null
    echo "== governor CPU"; cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor 2>/dev/null | sort | uniq -c
    echo "== antarmuka jaringan (kecepatan tautan)"
    for n in /sys/class/net/*; do
      [ -r "$n/speed" ] && printf '%s %s Mb/s\n' "$(basename "$n")" "$(cat "$n/speed" 2>/dev/null)"
    done
    echo "== kontainer Docker"; docker ps --format '{{.Names}}  {{.Image}}  {{.Status}}' 2>/dev/null || echo "(docker tidak dapat diakses; jalankan dengan sudo bila perlu)"
    echo "== layanan aktif";    systemctl list-units --type=service --state=running --no-legend 2>/dev/null | awk '{print $1}'
    echo "== Wi-Fi"
    for ifc in $(antarmuka_wifi); do
      echo "-- $ifc"; iw dev "$ifc" info 2>/dev/null; iw dev "$ifc" link 2>/dev/null
      iw dev "$ifc" get power_save 2>/dev/null
    done
    iw reg get 2>/dev/null | head -n 3
    cat /proc/net/wireless 2>/dev/null
    if di_wsl; then
      echo "== Windows (WSL terdeteksi)"
      ps_win '$o = Get-CimInstance Win32_OperatingSystem; "$($o.Caption) versi $($o.Version) build $($o.BuildNumber)"'
      echo "-- wsl --version";      winexe wsl.exe --version 2>/dev/null | tr -d '\000\r'
      echo "-- skema daya aktif";   winexe powercfg.exe /getactivescheme 2>/dev/null | tr -d '\r'
      echo "-- hemat daya Wi-Fi (AC): $(hemat_daya_windows)"
      echo "-- /etc/wsl.conf";      cat /etc/wsl.conf 2>/dev/null || echo "(tidak ada)"
      echo "-- .wslconfig"
      ps_win 'if (Test-Path "$env:USERPROFILE\.wslconfig") { Get-Content "$env:USERPROFILE\.wslconfig" } else { "(tidak ada)" }'
      echo "-- Wi-Fi Windows (netsh)"; wifi_windows
    fi
    echo "== uptime";           uptime
  } > "$berkas" 2>&1
  catat_wifi "$dev"

  pesan "Mengukur kondisi idle selama ${IDLE_DETIK} detik (S0). Jangan mengakses server selama pengukuran."
  # Hanya vmstat yang berjalan selama jendela idle; data mentah disimpan untuk diperiksa.
  local cpu mem suhu cpuwin="NA" rawvm="$HASIL_DIR/vmstat_idle_${dev}.txt"
  vmstat -n 1 $((IDLE_DETIK + 1)) > "$rawvm"
  cpu=$(cpu_sibuk_dari_vmstat < "$rawvm")
  mem=$(free -m | awk '/^Mem:/{print $3","$2}')
  suhu=$(suhu_maks)
  pesan "Selesai: CPU ${cpu}% | memori terpakai/total ${mem/,//} MB | suhu ${suhu} C"
  pesan "  rincian CPU (rata-rata %): $(rincian_vmstat < "$rawvm")"

  if di_wsl; then
    # CPU Windows diukur SESUDAH jendela idle, agar pengukurnya tidak ikut membebani S0.
    pesan "Mengukur CPU Windows (seluruh mesin) selama ${WIN_DETIK} detik. Tetap jangan mengakses server."
    local tmpwin; tmpwin=$(mktemp)
    cpu_windows "$WIN_DETIK" "$tmpwin"
    cpuwin=$(awk 'NF{print $1; exit}' "$tmpwin")
    [[ "$cpuwin" =~ ^[0-9]+(\.[0-9]+)?$ ]] || cpuwin="NA"
    rm -f "$tmpwin"
    pesan "  CPU Windows (seluruh mesin, termasuk pengukurnya) rata-rata ${cpuwin}%"
  fi
  tulis_csv "$HASIL_DIR/idle.csv" "perangkat,cpu_idle_pct,mem_terpakai_mb,mem_total_mb,suhu_c,cpu_windows_pct" \
            "$dev,$cpu,$mem,$suhu,$cpuwin"
}

# ---------------------------------------------------------------- mode cpu --
mode_cpu() {
  [ $# -ge 1 ] || gagal "pemakaian: $0 cpu <perangkat>"
  local dev; dev=$(bersih "$1")
  perlu sysbench "Pasang dengan: sudo apt install sysbench"
  local semua; semua=$(nproc)
  local t skor suhu
  for t in 1 "$semua"; do
    pesan "sysbench CPU (S3) dengan $t thread selama ${CPU_DETIK} detik"
    skor=$(sysbench cpu --cpu-max-prime=20000 --threads="$t" --time="$CPU_DETIK" run \
           | awk '/events per second/{print $NF}')
    suhu=$(suhu_maks)
    tulis_csv "$HASIL_DIR/cpu.csv" "perangkat,thread,event_per_detik,suhu_akhir_c" "$dev,$t,${skor:-NA},$suhu"
    pesan "  skor ${skor:-NA} event/detik, suhu akhir ${suhu} C"
    sleep 15
  done
}

# -------------------------------------------------------------- mode klien --
ke_ms() {
  # mengubah satuan waktu wrk (us, ms, s, m) menjadi milidetik
  awk -v v="$1" 'BEGIN{
    if (v ~ /us$/) { sub(/us$/, "", v); printf "%.3f", v/1000; exit }
    if (v ~ /ms$/) { sub(/ms$/, "", v); printf "%.3f", v;      exit }
    if (v ~ /m$/)  { sub(/m$/,  "", v); printf "%.3f", v*60000; exit }
    if (v ~ /s$/)  { sub(/s$/,  "", v); printf "%.3f", v*1000; exit }
    printf "NA" }'
}

urai_wrk() {
  # urai_wrk <berkas_keluaran_wrk>  ->  "req_s,lat_avg_ms,lat_p99_ms,total_req,galat_pct"
  local f="$1" rps lat p99 total non2xx sock
  rps=$(awk '/^Requests\/sec:/{print $2}' "$f")
  lat=$(awk '$1=="Latency" && !d {print $2; d=1}' "$f")
  p99=$(awk '$1=="99%"{print $2}' "$f")
  total=$(awk '/ requests in /{print $1}' "$f")
  non2xx=$(awk -F: '/Non-2xx or 3xx responses/{gsub(/ /,"",$2); print $2}' "$f")
  sock=$(awk '/Socket errors:/{gsub(/,/,""); print $4+$6+$8+$10}' "$f")
  total=${total:-0}; non2xx=${non2xx:-0}; sock=${sock:-0}
  local galat
  galat=$(awk -v t="$total" -v n="$non2xx" -v s="$sock" \
          'BEGIN{ if (t+s>0) printf "%.2f", 100*(n+s)/(t+s); else printf "100.00" }')
  printf '%s,%s,%s,%s,%s' "${rps:-0}" "$(ke_ms "${lat:-NA}")" "$(ke_ms "${p99:-NA}")" "$total" "$galat"
}

mode_klien() {
  [ $# -ge 3 ] || gagal "pemakaian: $0 klien <perangkat> <url_statis> <url_dinamis> [ssh_target]"
  local dev url_s url_d ssh_t
  dev=$(bersih "$1"); url_s="$2"; url_d="$3"; ssh_t="${4:-}"
  perlu wrk "Pasang dengan: sudo apt install wrk"

  if [ -n "$ssh_t" ]; then
    ssh -o BatchMode=yes -o ConnectTimeout=5 "$ssh_t" true 2>/dev/null \
      || gagal "SSH ke '$ssh_t' gagal. Pasang kunci SSH (ssh-copy-id $ssh_t) atau jalankan tanpa ssh_target."
    pesan "Utilisasi CPU perangkat dipantau melalui SSH ($ssh_t)."
  else
    pesan "Tanpa ssh_target: kolom cpu_pct akan berisi NA."
  fi

  local tmp; tmp=$(mktemp -d)
  local n_total=0 n=0 skenario url c u
  for c in $KONEKSI; do n_total=$((n_total + 2 * ULANGAN)); done

  for skenario in statis dinamis; do
    if [ "$skenario" = statis ]; then url="$url_s"; else url="$url_d"; fi
    if [ "$PEMANASAN" -gt 0 ]; then
      # Pemanasan: memanaskan cache (opcache, MariaDB, worker PHP-FPM); hasilnya tidak masuk beban.csv.
      local tp=$(( KONEKSI_SEDANG < 4 ? KONEKSI_SEDANG : 4 ))
      pesan "Pemanasan $skenario: ${PEMANASAN} detik, ${KONEKSI_SEDANG} koneksi (tidak dicatat di beban.csv)"
      wrk -t"$tp" -c"$KONEKSI_SEDANG" -d"${PEMANASAN}s" --timeout 5s --latency "$url" \
        > "$HASIL_DIR/wrk_${dev}_${skenario}_pemanasan.txt" 2>&1
      sleep "$JEDA"
    fi
    for c in $KONEKSI; do
      for u in $(seq 1 "$ULANGAN"); do
        n=$((n + 1))
        local t=$(( c < 4 ? c : 4 ))
        pesan "[$n/$n_total] $dev | $skenario | $c koneksi | ulangan $u | ${DURASI} detik"
        local vmpid=""
        if [ -n "$ssh_t" ]; then
          ssh -o BatchMode=yes "$ssh_t" "vmstat -n 1 $((DURASI + 2))" > "$tmp/vm" 2>/dev/null &
          vmpid=$!
          sleep 1
        fi
        wrk -t"$t" -c"$c" -d"${DURASI}s" --timeout 5s --latency "$url" > "$tmp/wrk" 2>&1
        local cpu="NA"
        if [ -n "$vmpid" ]; then wait "$vmpid"; cpu=$(cpu_sibuk_dari_vmstat < "$tmp/vm"); fi
        local hasil; hasil=$(urai_wrk "$tmp/wrk")
        cp "$tmp/wrk" "$HASIL_DIR/wrk_${dev}_${skenario}_c${c}_u${u}.txt"
        tulis_csv "$HASIL_DIR/beban.csv" \
          "perangkat,skenario,koneksi,ulangan,req_per_detik,lat_avg_ms,lat_p99_ms,total_req,galat_pct,cpu_pct" \
          "$dev,$skenario,$c,$u,$hasil,$cpu"
        pesan "  hasil: $hasil | CPU ${cpu}%"
        [ "$n" -lt "$n_total" ] && sleep "$JEDA"
      done
    done
  done

  # S4: throughput jaringan
  if command -v iperf3 >/dev/null 2>&1; then
    local host="${IPERF_HOST:-$(printf '%s' "$url_s" | sed -E 's#^[a-zA-Z]+://([^/:]+).*#\1#')}"
    pesan "iperf3 (S4) ke $host. Pastikan 'iperf3 -s' sudah berjalan di perangkat uji."
    for u in $(seq 1 "$ULANGAN"); do
      local mbit
      mbit=$(iperf3 -c "$host" -t "$IPERF_DETIK" -f m 2>/dev/null | awk '/receiver/{print $(NF-2)}' | tail -n 1)
      if [ -n "$mbit" ]; then
        tulis_csv "$HASIL_DIR/jaringan.csv" "perangkat,ulangan,mbit_per_detik" "$dev,$u,$mbit"
        pesan "  ulangan $u: $mbit Mbit/s"
      else
        pesan "  iperf3 gagal terhubung ke $host; langkah S4 dilewati."
        break
      fi
      sleep 5
    done
  else
    pesan "iperf3 tidak terpasang; langkah S4 dilewati."
  fi
  rm -rf "$tmp"
  pesan "Selesai. Data tersimpan di $HASIL_DIR/beban.csv dan $HASIL_DIR/jaringan.csv"
}

# --------------------------------------------------------------- mode daya --
mode_daya() {
  [ $# -ge 2 ] || gagal "pemakaian: $0 daya <perangkat> <idle|sedang|tinggi> [durasi_detik]"
  local dev kondisi dur
  dev=$(bersih "$1"); kondisi="$2"; dur="${3:-300}"
  case "$kondisi" in idle|sedang|tinggi) ;; *) gagal "kondisi harus idle, sedang, atau tinggi";; esac
  local n=$((dur / INTERVAL_DAYA)) mulai i w target kini
  pesan "Pencatatan daya $dev ($kondisi): $n pembacaan, tiap ${INTERVAL_DAYA} detik."
  case "$kondisi" in
    sedang) pesan "Jalankan beban di terminal lain:  $0 beban sedang <url_dinamis> $((dur + 30))";;
    tinggi) pesan "Jalankan beban di perangkat uji:  $0 beban tinggi $((dur + 30))";;
    idle)   pesan "Pastikan tidak ada akses ke server selama pencatatan.";;
  esac

  if [ "$VIDEO" = 1 ]; then
    # Mode VIDEO: tidak ada ketikan. Bip + jam tiap interval menjadi penanda pada rekaman;
    # angka watt dibaca kemudian dari video pada detik-detik penanda tersebut.
    pesan "Mode VIDEO: rekam layar wattmeter DAN terminal ini dalam satu bingkai; suara laptop dinyalakan."
    read -r -p "Mulai merekam video, lalu tekan Enter... " _
    mulai=$(date +%s)
    pesan "MULAI $dev $kondisi"
    for ((i = 1; i <= n; i++)); do
      target=$((mulai + i * INTERVAL_DAYA)); kini=$(date +%s)
      [ "$target" -gt "$kini" ] && sleep $((target - kini))
      printf '\a[%s] PENANDA %2d/%d  (detik ke-%d)\n' "$(date +%H:%M:%S)" "$i" "$n" $((i * INTERVAL_DAYA))
    done
    pesan "SELESAI $dev $kondisi. Hentikan rekaman video."
    tulis_csv "$HASIL_DIR/daya_video.csv" "perangkat,kondisi,mulai,selesai,interval_detik,jumlah_penanda" \
      "$dev,$kondisi,$(date -d "@$mulai" -Iseconds),$(date -Iseconds),$INTERVAL_DAYA,$n"
    return
  fi

  pesan "Ketik angka watt dari wattmeter saat diminta (desimal memakai titik, mis. 7.4)."
  read -r -p "Tekan Enter untuk mulai... " _
  mulai=$(date +%s)
  for ((i = 1; i <= n; i++)); do
    target=$((mulai + i * INTERVAL_DAYA)); kini=$(date +%s)
    [ "$target" -gt "$kini" ] && sleep $((target - kini))
    while true; do
      printf '\a[%4d detik] Watt: ' $((i * INTERVAL_DAYA))
      read -r w
      w="${w//,/.}"
      [[ "$w" =~ ^[0-9]+(\.[0-9]+)?$ ]] && break
      echo "  Masukan tidak valid, ulangi."
    done
    tulis_csv "$HASIL_DIR/daya.csv" "perangkat,kondisi,detik_ke,watt" "$dev,$kondisi,$((i * INTERVAL_DAYA)),$w"
  done
  awk -F, -v d="$dev" -v k="$kondisi" '$1==d && $2==k {s+=$4; n++}
       END{ if(n) printf "Rata-rata daya %s (%s): %.2f W dari %d pembacaan\n", d, k, s/n, n }' \
      "$HASIL_DIR/daya.csv"
}

# -------------------------------------------------------------- mode beban --
mode_beban() {
  [ $# -ge 1 ] || gagal "pemakaian: $0 beban sedang <url_dinamis> [durasi] | $0 beban tinggi [durasi]"
  case "$1" in
    sedang)
      [ $# -ge 2 ] || gagal "pemakaian: $0 beban sedang <url_dinamis> [durasi]"
      perlu wrk "Pasang dengan: sudo apt install wrk"
      local dur="${3:-330}"
      pesan "Beban sedang: $KONEKSI_SEDANG koneksi ke $2 selama $dur detik"
      wrk -t4 -c"$KONEKSI_SEDANG" -d"${dur}s" --timeout 5s "$2"
      ;;
    tinggi)
      perlu sysbench "Pasang dengan: sudo apt install sysbench"
      local dur="${2:-330}"
      pesan "Beban tinggi: sysbench CPU $(nproc) thread selama $dur detik"
      sysbench cpu --cpu-max-prime=20000 --threads="$(nproc)" --time="$dur" run | awk '/events per second/'
      ;;
    *) gagal "jenis beban harus 'sedang' atau 'tinggi'";;
  esac
}

# ------------------------------------------------------------ mode ringkas --
mode_ringkas() {
  local B="$HASIL_DIR/beban.csv" D="$HASIL_DIR/daya.csv"
  local RB="$HASIL_DIR/ringkasan_beban.csv" RD="$HASIL_DIR/ringkasan_daya.csv" EF="$HASIL_DIR/efisiensi.csv"

  if [ -f "$B" ]; then
    awk -F, 'NR>1 {
        k=$1","$2","$3; n[k]++
        for (j=5; j<=10; j++) if ($j != "NA") { s[k,j]+=$j; q[k,j]+=$j*$j; m[k,j]++ }
      }
      END {
        print "perangkat,skenario,koneksi,n,req_per_detik_rata,req_per_detik_sd,lat_avg_ms_rata,lat_p99_ms_rata,lat_p99_ms_sd,total_req_rata,galat_pct_rata,cpu_pct_rata"
        for (k in n) {
          printf "%s,%d", k, n[k]
          for (j=5; j<=10; j++) {
            if (m[k,j] > 0) { r = s[k,j]/m[k,j]; v = (m[k,j] > 1) ? (q[k,j] - m[k,j]*r*r)/(m[k,j]-1) : 0; if (v < 0) v = 0; sd = sqrt(v) }
            else { r = "NA"; sd = "NA" }
            if (j==5)  printf ",%s,%s", fmt(r), fmt(sd)
            if (j==6)  printf ",%s", fmt(r)
            if (j==7)  printf ",%s,%s", fmt(r), fmt(sd)
            if (j==8 || j==9 || j==10) printf ",%s", fmt(r)
          }
          printf "\n"
        }
      }
      function fmt(x) { return (x == "NA") ? "NA" : sprintf("%.2f", x) }' "$B" \
      | { IFS= read -r h; echo "$h"; sort -t, -k1,1 -k2,2 -k3,3n; } > "$RB"
    pesan "Ringkasan beban: $RB"
  else
    pesan "beban.csv belum ada; ringkasan beban dilewati."
  fi

  if [ -f "$D" ]; then
    awk -F, 'NR>1 { k=$1","$2; s[k]+=$4; q[k]+=$4*$4; n[k]++ }
      END { print "perangkat,kondisi,n,watt_rata,watt_sd"
            for (k in n) { r=s[k]/n[k]; v=(n[k]>1)?(q[k]-n[k]*r*r)/(n[k]-1):0; if(v<0)v=0
                           printf "%s,%d,%.2f,%.2f\n", k, n[k], r, sqrt(v) } }' "$D" \
      | { IFS= read -r h; echo "$h"; sort -t, -k1,1 -k2,2; } > "$RD"
    pesan "Ringkasan daya: $RD"
  else
    pesan "daya.csv belum ada; ringkasan daya dilewati."
  fi

  if [ -f "$RB" ] && [ -f "$RD" ]; then
    awk -F, -v ks="$KONEKSI_SEDANG" -v bp="$BATAS_P99_MS" -v bg="$BATAS_GALAT" -v tarif="$TARIF" '
      FNR==1 { berkas++; next }
      berkas==1 {
        dev[$1]=1
        if ($2=="dinamis" && $3==ks) x[$1]=$5
        # kolom ringkasan: 8 = lat_p99_ms_rata, 11 = galat_pct_rata
        if ($8 != "NA" && $11 != "NA" && $8+0 <= bp && $11+0 < bg) {
          if ($3+0 > kap[$1","$2]+0) kap[$1","$2]=$3
        }
      }
      berkas==2 { dev[$1]=1; p[$1","$2]=$4 }
      END {
        print "perangkat,throughput_dinamis_c" ks ",daya_idle_w,daya_sedang_w,daya_tinggi_w,rasio_idle_tinggi,kinerja_per_watt,energi_per_permintaan_j,energi_tahunan_idle_kwh,biaya_tahunan_rp,kapasitas_statis,kapasitas_dinamis"
        for (d in dev) {
          pi=p[d",idle"]; ps=p[d",sedang"]; pt=p[d",tinggi"]; xx=x[d]
          rasio = (pi!="" && pt!="" && pt>0) ? sprintf("%.2f", pi/pt) : "NA"
          ppw   = (xx!="" && ps!="" && ps>0) ? sprintf("%.2f", xx/ps) : "NA"
          jpr   = (xx!="" && xx>0 && ps!="") ? sprintf("%.4f", ps/xx) : "NA"
          ekwh  = (pi!="") ? sprintf("%.2f", pi*8760/1000) : "NA"
          biaya = (pi!="" && tarif!="") ? sprintf("%.0f", pi*8760/1000*tarif) : "NA"
          printf "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n", d, (xx!=""?xx:"NA"), (pi!=""?pi:"NA"), (ps!=""?ps:"NA"), (pt!=""?pt:"NA"),
                 rasio, ppw, jpr, ekwh, biaya, (kap[d",statis"]!=""?kap[d",statis"]:"NA"), (kap[d",dinamis"]!=""?kap[d",dinamis"]:"NA")
        }
      }' "$RB" "$RD" | { IFS= read -r h; echo "$h"; sort; } > "$EF"
    pesan "Indikator efisiensi: $EF"
    echo
    column -s, -t < "$EF" 2>/dev/null || cat "$EF"
  fi
}

# ------------------------------------------------------------------- utama --
bantuan() { awk 'NR>1 && /^#/{sub(/^# ?/, ""); print; next} NR>1{exit}' "$0"; }

[ $# -ge 1 ] || { bantuan; exit 1; }
mode="$1"; shift
case "$mode" in
  info)    mode_info "$@";;
  cpu)     mode_cpu "$@";;
  klien)   mode_klien "$@";;
  daya)    mode_daya "$@";;
  beban)   mode_beban "$@";;
  ringkas) mode_ringkas;;
  -h|--help|bantuan) bantuan;;
  *) bantuan; exit 1;;
esac
