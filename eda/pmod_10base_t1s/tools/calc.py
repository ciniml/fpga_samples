#!/usr/bin/env python3
"""10BASE-T1S Pmod (PHY チップなし) の机上計算。README の数値の根拠。

実行: python3 calc.py
値は README §3 の回路案に合わせる。推定値 (FPGA のピン容量など) は実測で置き換えること。
"""
import math

VCCIO = 3.3
R_LOAD_DIFF = 50.0          # 100 Ω 終端 x2 (バスの両端) の並列

# ---- 送信 (片側) ----
def tx(r_pin, r1, r_on, r2, c1, vcc=VCCIO):
    rt = r_pin + r1 + r_on + r2                 # ピンから線路までの直列抵抗 (片側)
    vpk = vcc * R_LOAD_DIFF / (R_LOAD_DIFF + 2 * rt)   # 差動ピーク (±)
    rth = 1 / (1 / (r_pin + r1) + 1 / (r_on + r2 + R_LOAD_DIFF / 2))
    tau = rth * c1
    return rt, 2 * vpk, tau * math.log(4) , 2 * rt   # Vpp, t20-80, 出力インピーダンス(差動)

print("== 送信: 振幅と立ち上がり (R1=100, Ron=2, R2=18, C1=220p)")
for r_pin in (15, 20, 30):
    for vcc in (3.135, 3.3, 3.465):
        rt, vpp, t2080, zout = tx(r_pin, 100, 2, 18, 220e-12, vcc)
        print(f"  Rpin={r_pin:2d} VCCIO={vcc:.3f}: Vpp={vpp:.3f} V (規格 0.8-1.2)  "
              f"t20-80={t2080*1e9:4.1f} ns (OA 7.5-15)  Zout={zout:.0f} Ω")

print("== 送信: C1 と立ち上がり (Rpin=20)")
for c1 in (100e-12, 150e-12, 220e-12, 330e-12):
    print(f"  C1={c1*1e12:.0f} pF: t20-80={tx(20,100,2,18,c1)[2]*1e9:.1f} ns")

# ---- 休止中 (high-Z) のインピーダンス: 差動 ----
def z_limit(f):            # 802.3cg 式 147-8 (OA PMA 試験仕様 5.3.1): 10 kΩ || 25 pF
    return 1 / math.sqrt((1 / 10e3) ** 2 + (2 * math.pi * f * 25e-12) ** 2)

def z_node(f, r_par, c_wire):
    """r_par: 差動の並列抵抗, c_wire: 1 線あたりの対地容量 → 差動は c_wire/2"""
    c = c_wire / 2
    return 1 / math.sqrt((1 / r_par) ** 2 + (2 * math.pi * f * c) ** 2)

# 1 線あたりの対地容量の内訳 (pF)。FPGA ピン容量は推定。RX タップは 1 kΩ 直列で高域では見えにくいが安全側に全量を足す
C_PARTS = {
    "FPGA LVDS 入力 x2 (推定 5 pF/ピン)": 10.0,
    "TMUX1511 COFF (最大)": 4.0,
    "TPD4E02B04 (0.25 pF)": 0.3,
    "配線・パッド": 2.0,
}
C_CMC = 10.0   # OA の目安 (CMC 10 pF を差動側に) — 差動で加算
c_wire = sum(C_PARTS.values())
# 並列抵抗 (差動): RX バイアス 20 kΩ x2 タップ/線 → 10 kΩ/線 → 差動 20 kΩ、スイッチ側バイアス 100 kΩ/線 → 200 kΩ
r_par = 1 / (1 / 20e3 + 1 / 200e3)
print(f"== 休止中のインピーダンス (差動 R={r_par/1e3:.1f} kΩ, 1 線 {c_wire:.1f} pF → 差動 {c_wire/2:.1f} pF, CMC +{C_CMC} pF)")
for f in (0.3e6, 1e6, 5e6, 12.5e6, 25e6, 40e6):
    zn = 1 / math.sqrt((1 / r_par) ** 2 + (2 * math.pi * f * (c_wire / 2 + C_CMC) * 1e-12) ** 2)
    zl = z_limit(f)
    print(f"  {f/1e6:5.1f} MHz: |Z|={zn:7.0f} Ω  下限={zl:7.0f} Ω  {'OK' if zn >= zl else 'NG'}")
print(f"  差動容量の合計 {c_wire/2 + C_CMC:.1f} pF (OA の上限 CMDI 25 pF)")

# ---- 受信: しきい値 (PWM → Vth) ----
VB = 3.3 * 1.2 / (2.2 + 1.2)
RP1, RP2 = 5.6e3, 1e3
k = RP2 / (RP1 + RP2)
print(f"== 受信しきい値: VB={VB:.3f} V, k={k:.3f}")
print(f"  th = (D*3.3 - VB)*k: D=0 → {(-VB)*k*1e3:.0f} mV, D=1 → {(3.3-VB)*k*1e3:.0f} mV, "
      f"10bit 1LSB={3.3*k/1024*1e3:.2f} mV")
# RX タップの高域通過: 0.1 µF と 20 kΩ
print(f"  RX タップ HPF: {1/(2*math.pi*0.1e-6*20e3):.0f} Hz")

# ---- タイミング ----
print("== タイミング")
print("  1 ビット 80 ns、半ビット 40 ns、短区間 40 ns / 長区間 80 ns、判定境界 60 ns")
print("  ジッタ許容 15 ns p-p (OA 受信試験) → 区間の誤差 ±7.5 ns でも境界まで 12.5 ns の余裕")
for fs in (100e6, 150e6, 200e6, 300e6, 400e6):
    print(f"  {fs/1e6:.0f} MS/s: 分解能 {1e9/fs:.2f} ns, 半ビット {40e-9*fs:.1f} サンプル")
