#!/usr/bin/env python3
"""Reproduce the four figures of the manuscript from the raw data in this repository.

Usage (from the repository root):  python3 analysis/make_figures.py
Output: figures/*.png (300 dpi) and figures/*.tif (600 dpi).
Requires: matplotlib.
"""
import csv, statistics as st, os
from pathlib import Path
import logging
import matplotlib
matplotlib.use('Agg')
logging.getLogger('matplotlib.font_manager').setLevel(logging.ERROR)
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

REPO = Path(__file__).resolve().parent.parent
H = str(REPO / 'data' / 'client')
OUT = str(REPO / 'figures')
os.makedirs(OUT, exist_ok=True)

DEV = ['ryzen', 'intel', 'arm']
LAB = {'ryzen': 'Ryzen mini PC', 'intel': 'Intel mini PC', 'arm': 'ARM mini PC'}
COL = {'ryzen': '#2a78d6', 'intel': '#eb6834', 'arm': '#1baf7a'}   # validated categorical slots 1-3
MRK = {'ryzen': 'o', 'intel': 's', 'arm': '^'}
LS = {'ryzen': '-', 'intel': '--', 'arm': ':'}
INK, INK2, GRID = '#0b0b0b', '#52514e', '#d9d8d4'

plt.rcParams.update({
    'font.family': 'sans-serif', 'font.sans-serif': ['Liberation Sans', 'Arial', 'Helvetica', 'DejaVu Sans'], 'font.size': 8, 'axes.titlesize': 8.5,
    'axes.labelsize': 8, 'xtick.labelsize': 7.5, 'ytick.labelsize': 7.5, 'legend.fontsize': 7.5,
    'axes.edgecolor': INK2, 'axes.labelcolor': INK, 'xtick.color': INK2, 'ytick.color': INK2,
    'axes.spines.top': False, 'axes.spines.right': False, 'axes.linewidth': 0.6,
    'xtick.major.width': 0.6, 'ytick.major.width': 0.6, 'savefig.facecolor': 'white',
})

def save(fig, name):
    fig.savefig(f'{OUT}/{name}.png', dpi=300, bbox_inches='tight')
    fig.savefig(f'{OUT}/{name}.tif', dpi=600, bbox_inches='tight',
                pil_kwargs={'compression': 'tiff_lzw'})
    plt.close(fig)

# ---------------------------------------------------------------- data --
beban = list(csv.DictReader(open(f'{H}/beban.csv')))
CONN = [10, 25, 50, 100]
def agg(dev, sk, col):
    m, s = [], []
    for c in CONN:
        v = [float(r[col]) for r in beban if r['perangkat'] == dev and r['skenario'] == sk and int(r['koneksi']) == c]
        assert len(v) == 3
        m.append(st.mean(v)); s.append(st.stdev(v))
    return m, s

daya = list(csv.reader(open(f'{H}/daya.csv')))[1:]
arm_p1 = list(csv.reader(open(f'{H}/daya_arm_sedang_percobaan1.csv')))
def pw(dev, kond):
    rows = arm_p1 if (dev, kond) == ('arm', 'sedang') else daya
    v = [float(r[3]) for r in rows if r[0] == dev and r[1] == kond]
    assert len(v) == 30
    return st.mean(v), st.stdev(v)

# ------------------------------------------------- Fig 2: throughput ----
def line_panel(ax, sk, col, ylabel, title, slo=None):
    for d in DEV:
        m, s = agg(d, sk, col)
        ax.errorbar(CONN, m, yerr=s, color=COL[d], marker=MRK[d], ls=LS[d], lw=1.6, ms=5,
                    capsize=2.5, elinewidth=0.8, label=LAB[d], mec='white', mew=0.6)
    ax.set_xscale('log')
    ax.set_xticks(CONN); ax.set_xticklabels([str(c) for c in CONN]); ax.minorticks_off()
    ax.set_xlabel('Concurrent connections')
    ax.set_ylabel(ylabel)
    ax.set_title(title, loc='left', color=INK, fontweight='bold')
    ax.grid(axis='y', color=GRID, lw=0.5)
    ax.set_ylim(bottom=0)
    if slo:
        ax.axhline(slo, color=INK2, lw=0.9, ls=(0, (4, 3)), label='SLO (p99 = 1000 ms)')

fig, axs = plt.subplots(1, 2, figsize=(6.6, 2.6))
line_panel(axs[0], 'statis', 'req_per_detik', 'Throughput (requests/s)', '(a) Static content')
line_panel(axs[1], 'dinamis', 'req_per_detik', 'Throughput (requests/s)', '(b) Dynamic content')
axs[1].set_ylim(0, 1100); axs[0].set_ylim(0, 1100)
h, l = axs[0].get_legend_handles_labels()
fig.legend(h, l, loc='upper center', ncol=3, frameon=False, bbox_to_anchor=(0.5, 1.07))
fig.tight_layout()
save(fig, 'fig2_throughput')

# ------------------------------------------------------ Fig 3: p99 ------
fig, axs = plt.subplots(1, 2, figsize=(6.6, 2.6))
line_panel(axs[0], 'statis', 'lat_p99_ms', 'p99 response time (ms)', '(a) Static content', slo=1000)
line_panel(axs[1], 'dinamis', 'lat_p99_ms', 'p99 response time (ms)', '(b) Dynamic content', slo=1000)
for a in axs:
    a.set_ylim(0, 2600)
h, l = axs[0].get_legend_handles_labels()
fig.legend(h, l, loc='upper center', ncol=4, frameon=False, bbox_to_anchor=(0.5, 1.07))
fig.tight_layout()
save(fig, 'fig3_p99')

# -------------------------------------- Fig 4: power and perf-per-watt --
fig, axs = plt.subplots(1, 2, figsize=(6.6, 2.6), gridspec_kw={'width_ratios': [1.45, 1]})
ax = axs[0]
states = [('idle', 'Idle'), ('sedang', 'Medium load'), ('tinggi', 'High load')]
w = 0.26
for i, d in enumerate(DEV):
    xs, ms, ss = [], [], []
    for j, (k, _) in enumerate(states):
        m, s = pw(d, k)
        xs.append(j + (i - 1) * (w + 0.02)); ms.append(m); ss.append(s)
    bars = ax.bar(xs, ms, width=w, color=COL[d], yerr=ss, capsize=2, error_kw={'elinewidth': 0.7},
                  label=LAB[d], edgecolor='white', linewidth=0.8)
    for x, m, sd in zip(xs, ms, ss):
        ax.text(x, m + sd + 0.6, f'{m:.1f}', ha='center', va='bottom', fontsize=6.5, color=INK)
ax.set_xticks(range(3)); ax.set_xticklabels([s for _, s in states])
ax.set_ylabel('Wall power (W)'); ax.set_ylim(0, 48)
ax.grid(axis='y', color=GRID, lw=0.5); ax.set_axisbelow(True)
ax.set_title('(a) Power by load state', loc='left', color=INK, fontweight='bold')

ax = axs[1]
thr = {d: agg(d, 'dinamis', 'req_per_detik')[0][1] for d in DEV}   # 25 connections
ppw = {d: thr[d] / pw(d, 'sedang')[0] for d in DEV}
xs = range(3)
ax.bar(xs, [ppw[d] for d in DEV], color=[COL[d] for d in DEV], width=0.6, edgecolor='white')
for x, d in zip(xs, DEV):
    ax.text(x, ppw[d] + 1, f'{ppw[d]:.1f}', ha='center', va='bottom', fontsize=7, color=INK)
ax.set_xticks(list(xs)); ax.set_xticklabels(['Ryzen', 'Intel', 'ARM'])
ax.set_ylabel('Requests/s per watt'); ax.set_ylim(0, 60)
ax.grid(axis='y', color=GRID, lw=0.5); ax.set_axisbelow(True)
ax.set_title('(b) Performance per watt', loc='left', color=INK, fontweight='bold')
h, l = axs[0].get_legend_handles_labels()
fig.legend(h, l, loc='upper center', ncol=3, frameon=False, bbox_to_anchor=(0.5, 1.07))
fig.tight_layout()
save(fig, 'fig4_power_ppw')
print('performance per watt:', {d: round(ppw[d], 2) for d in DEV})

# --------------------------------------------------- Fig 1: testbed -----
fig, ax = plt.subplots(figsize=(6.6, 3.2))
ax.set_xlim(0, 100); ax.set_ylim(0, 48); ax.axis('off')
def box(x, y, w, h, text, fc='#ffffff', ec=INK2, fs=7.2, bold=False, lw=0.8):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle='round,pad=0.3,rounding_size=1.0',
                                fc=fc, ec=ec, lw=lw))
    ax.text(x + w / 2, y + h / 2, text, ha='center', va='center', fontsize=fs, color=INK,
            fontweight='bold' if bold else 'normal', linespacing=1.25)
def arrow(x1, y1, x2, y2, both=True):
    ax.add_patch(FancyArrowPatch((x1, y1), (x2, y2), arrowstyle='<|-|>' if both else '-|>',
                                 mutation_scale=7, lw=0.8, color=INK2))
# device under test
X0, W0 = 33, 36
ax.add_patch(FancyBboxPatch((X0, 3), W0, 41, boxstyle='round,pad=0.3,rounding_size=1.4',
                            fc='#f4f3f0', ec=INK2, lw=0.9))
ax.text(X0 + W0 / 2, 41.2, 'Device under test (one at a time)', ha='center', fontsize=7.4,
        fontweight='bold', color=INK)
ax.text(X0 + W0 / 2, 38.4, 'Ryzen, Intel, or ARM mini PC', ha='center', fontsize=6.6, color=INK2)
cw, gap = 10.4, 1.2
cx = X0 + 1.4
for i, (t, c, f) in enumerate([('Nginx\n1.27', COL['ryzen'], '#e9f1fb'),
                                ('PHP-FPM\n8.3', COL['intel'], '#fdeee7'),
                                ('MariaDB\n11.4', COL['arm'], '#e6f6f0')]):
    box(cx + i * (cw + gap), 27.5, cw, 7.5, t, fc=f, ec=c, fs=6.9)
inner_w = 3 * cw + 2 * gap
box(cx, 19.8, inner_w, 4.6, 'Docker Engine + CasaOS', fs=6.9)
box(cx, 12.4, inner_w, 4.6, 'Ubuntu 26.04 or Armbian (Ubuntu 24.04)', fs=6.6)
box(cx, 5.0, inner_w, 4.6, 'Hardware with 2.4 GHz Wi-Fi', fs=6.6)
# client and access point
box(2, 27.5, 22, 11, 'Client laptop\nwrk, iperf3,\npower-logging script', fs=7)
box(2, 5.0, 22, 9, 'Wi-Fi access point\n2.4 GHz, 802.11n', fs=7)
arrow(13, 14.6, 13, 26.9)
ax.text(14.2, 19.8, 'Wi-Fi', fontsize=6.5, color=INK2)
arrow(24.6, 9.5, X0 + 0.9, 9.5)
ax.text((24.6 + X0) / 2, 10.6, 'Wi-Fi', fontsize=6.5, color=INK2, ha='center')
ax.text(13, 1.2, 'HTTP load (10–100 connections), iperf3, SSH', fontsize=6.2, color=INK2, ha='center')
# wattmeter and tunnel
box(75, 7.0, 23, 9, 'AC plug-in wattmeter\n(0.1 W resolution)', fs=6.9)
arrow(74.4, 11.5, X0 + W0 + 0.7, 11.5, both=False)
ax.text(86.5, 1.2, 'read every 10 s and typed\ninto the client logger', fontsize=6.2, color=INK2,
        ha='center', va='bottom', linespacing=1.15)
box(75, 24.5, 23, 9, 'Cloudflare Tunnel\n(cloudflared)', fs=6.9)
arrow(X0 + W0 + 0.7, 29.0, 74.4, 29.0)
box(75, 39.5, 23, 5.0, 'Public users (optional)', fs=6.6, ec='#9a9893')
arrow(86.5, 34.1, 86.5, 38.9)
save(fig, 'fig1_testbed')
print('done')
