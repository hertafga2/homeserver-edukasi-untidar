# Repurposed mini PCs and an ARM set-top box as educational web servers: test script, test application, and raw data

This repository contains the test script, the containerized test application, and all raw measurements behind the article

> Arfanindita HT, Husain F, Mardiyah S, Karini ND, Mahardhika W, Mas'udan MA, Simarmata RH. *Energy-Efficient Educational Web Hosting on Repurposed Hardware: Concurrent Load, Tail Latency, and Performance per Watt of x86 and ARM Mini Computers.* Manuscript submitted to *Concurrency and Computation: Practice and Experience*.

The study compares three repurposed devices running an identical web stack (Nginx, PHP-FPM, and MariaDB on Docker) over 2.4 GHz Wi-Fi. It measures throughput, mean and 99th-percentile response time, and CPU utilization at 10, 25, 50, and 100 concurrent connections, together with wall power at idle, medium, and high load.

| Label in data | Device | Processor | Operating system |
|---|---|---|---|
| `ryzen` | HP ProDesk 405 G4 Desktop Mini | AMD Ryzen 5 PRO 2400GE (4 cores/8 threads) | Ubuntu 26.04 LTS under WSL2 on Windows 11 Pro |
| `intel` | Intel NUC5CPYH | Intel Celeron N3050 (2 cores) | Ubuntu Server 26.04.1 LTS |
| `arm` | ZTE B860H V2A set-top box | Amlogic S905X, ARM Cortex-A53 (4 cores) | Armbian 25.11.0 (Ubuntu 24.04) |

## Repository layout

```
scripts/uji_homeserver.sh      test script (load, CPU, network, and power logging)
app/paket_uji/                 test application deployed identically on all devices
data/client/                   files recorded on the client laptop
data/client/wrk_outputs.zip    original wrk output, 72 files (24 per device)
data/devices/<device>/         files recorded on each device under test
data/derived/                  summaries produced by the script's "ringkas" mode
analysis/make_figures.py       reproduces the four figures of the article
```

## Test application

`app/paket_uji` runs three containers with Docker Compose: Nginx 1.27, PHP-FPM 8.3 built from Alpine 3.23 packages (mysqli and OPcache), and MariaDB 11.4 seeded with 1,000 student records. The static page (`html/index.html`, 3.6 kB) is served at `http://<device>:8080/` and the dynamic page (`html/uji.php`) at `http://<device>:8080/uji.php`. The dynamic page queries the record count and mean score and lists the 50 highest scores on every request.

```bash
cd app/paket_uji
sudo docker compose up -d --build
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8080/uji.php   # expect 200
```

The database passwords in `docker-compose.yml`, `db/buat_db.sql`, and `html/uji.php` are test placeholders. The database port is not published outside the Compose network. Change the passwords before using the package for anything other than testing.

## Running the tests

`scripts/uji_homeserver.sh` documents its modes, parameters, and the full test order in its header (`./uji_homeserver.sh` without arguments prints it). The modes are:

| Mode | Runs on | Purpose | Output |
|---|---|---|---|
| `info <device>` | device | system information, then 300-s idle measurement with vmstat | `info_<device>.txt`, `vmstat_idle_<device>.txt`, `idle.csv`, `wifi.csv` |
| `cpu <device>` | device | sysbench CPU, primes up to 20,000, 30 s, one thread and all threads | `cpu.csv` |
| `klien <device> <static_url> <dynamic_url> [ssh]` | client | wrk at 10, 25, 50, 100 connections, 3 × 60 s, 30-s pause, 5-s timeout; CPU sampled over SSH; then iperf3 3 × 30 s | `beban.csv`, `wrk_*.txt` (in `wrk_outputs.zip`), `jaringan.csv` |
| `daya <device> <idle\|sedang\|tinggi> [s]` | client | records a wattmeter reading typed by the operator every 10 s for 300 s | `daya.csv` |
| `beban sedang <dynamic_url> [s]` | client | medium load: wrk, 25 connections, 330 s | terminal |
| `beban tinggi [s]` | device | high load: sysbench on all threads, 330 s | terminal |
| `ringkas` | client | means, standard deviations, capacity, and efficiency indicators | `ringkasan_beban.csv`, `ringkasan_daya.csv`, `efisiensi.csv` |

Required packages: `sysbench`, `procps`, `iperf3`, and `iw` on the device; `wrk`, `iperf3`, and `openssh-client` on the client.

## Data description

Column names and labels are in Indonesian, as written by the script. Decimal separators are dots.

**Common labels.** `perangkat` = device (`ryzen`, `intel`, `arm`); `skenario` = content type (`statis` = static, `dinamis` = dynamic); `kondisi` = load state (`idle`, `sedang` = medium, `tinggi` = high); `ulangan` = repetition.

| File | Columns |
|---|---|
| `data/client/beban.csv` | `perangkat`, `skenario`, `koneksi` (concurrent connections), `ulangan`, `req_per_detik` (requests/s), `lat_avg_ms` (mean response time, ms), `lat_p99_ms` (99th-percentile response time, ms), `total_req` (completed requests), `galat_pct` (errors, % = (non-2xx/3xx + socket errors) / (requests + socket errors)), `cpu_pct` (device CPU utilization, % = 100 − vmstat idle) |
| `data/client/daya.csv` | `perangkat`, `kondisi`, `detik_ke` (seconds since the start of recording), `watt` (wall power, W) |
| `data/client/daya_arm_sedang_percobaan1.csv` | same columns, no header row: first medium-load run of the ARM device |
| `data/client/jaringan.csv` | `perangkat`, `ulangan`, `mbit_per_detik` (iperf3 receiver throughput, client to device) |
| `data/devices/*/idle.csv` | `perangkat`, `cpu_idle_pct` (CPU utilization during the idle window, %), `mem_terpakai_mb` (memory used), `mem_total_mb`, `suhu_c` (CPU temperature, °C), `cpu_windows_pct` (Windows CPU utilization, Ryzen only) |
| `data/devices/*/cpu.csv` | `perangkat`, `thread`, `event_per_detik` (sysbench events/s), `suhu_akhir_c` (temperature at the end, °C) |
| `data/devices/*/wifi.csv` | `perangkat`, `antarmuka` (interface), `ssid`, `frekuensi_mhz`, `sinyal_dbm`, `laju_tx_mbit` (link rate), `hemat_daya` (Wi-Fi power saving), `sumber_sinyal` (source of the signal reading) |

## Notes on the data

- **Original wrk output.** The 72 wrk result files (`wrk_<device>_<statis|dinamis>_c<connections>_u<repetition>.txt`) are bundled in `data/client/wrk_outputs.zip`; `beban.csv` was parsed from them by the script.
- **Power readings** were read manually from a plug-in AC wattmeter with 0.1 W resolution, every 10 s for 300 s (30 readings per state), starting about 15 s after the load began. They include power-adapter losses.
- **Ryzen idle labels in `daya.csv`.** `ryzen` is the idle value used in the article (24.92 W; remote-desktop session active). `ryzen_pascarestart` is the first idle measurement after the device was restarted; power dropped to about 18 W whenever the remote session was inactive, so it was not used as the main value. `ryzen_windows` is idle power under Windows without WSL.
- **ARM medium load.** The article uses the first run (`daya_arm_sedang_percobaan1.csv`, 4.43 W at 135.2 requests/s). The `arm,sedang` rows in `daya.csv` are a repeated run (4.23 W at 204.5 requests/s) disturbed by a Wi-Fi interruption of about 30 s, which produced 24 timeouts (`wrk_arm_beban_sedang_ulang.txt`). The readings from 80 to 130 s are affected; without them the mean is 4.51 W.
- **Intel medium-load correction.** The reading at 50 s was first typed as 112.6 W and corrected to 12.5 W after checking the wattmeter; the reading at 200 s was confirmed as 12.4 W (`catatan_koreksi.txt`). The uncorrected file is kept as `daya_sebelum_koreksi_intel.csv`.
- **`daya_cadangan.csv`** is a backup copy written during the Ryzen session. It contains the first idle series (later labelled `ryzen_pascarestart`) and two readings from an aborted start of the high-load run; the final 30 high-load readings are identical to `daya.csv`.
- **`data/devices/arm/daya_b5_di_stb.csv`** is the ARM idle power series recorded on the device itself; it is identical to the `arm,idle` rows in `daya.csv`.
- **Derived files.** `data/derived/efisiensi.csv` was computed by the script from `daya.csv` and therefore uses the repeated ARM medium-load run (4.23 W). The article uses 4.43 W, giving 51.30 requests/s per watt (51.34 with unrounded power). Annual cost is `NA` because no tariff was passed to the script.
- **Anonymization.** MAC addresses, private IP addresses, interface GUIDs, the Ryzen host and user name, and the campus SSID were replaced with placeholders (`xx:xx:xx:xx:xx:xx`, `<private-ip>`, `<guid>`, `ryzen-host`, `user`, `CAMPUS-WIFI`). No measured value was changed.
- **Test conditions.** The Ryzen and Intel devices were tested on 13 November 2026 through the same access point on channel 6. The ARM device was tested on 14 November 2026 at another campus location through a different access point on channel 1.

## Reproducing the figures

```bash
pip install matplotlib
python3 analysis/make_figures.py      # writes figures/*.png and figures/*.tif
```

## License

The code (`scripts/`, `app/`, `analysis/`) is released under the MIT License (`LICENSE`). The data (`data/`) are released under the Creative Commons Attribution 4.0 International License (`LICENSE-DATA.md`).

## Citation

Please cite the article above and this repository. Citation metadata are in `CITATION.cff`; the archived version has a DOI assigned by Zenodo.

## Funding

Universitas Tidar, Stimulus Research scheme for Assistant Professors (Penelitian Stimulus Asisten Ahli), DIPA Universitas Tidar 2026, Rector's Decree No. 2076/DST/UN57/PT.01.00/2026.

## Contact

Her Tafga Arfanindita, Industrial Engineering Study Program, Faculty of Engineering, Universitas Tidar, Magelang, Indonesia. Email: hertafga@untidar.ac.id. ORCID: [0000-0001-9332-2452](https://orcid.org/0000-0001-9332-2452).
