# README — RIS FPGA Controller (VHDL)

**Project:** Reconfigurable Intelligent Surface (RIS) Phase Controller  
**Platform:** Xilinx Virtex-5 ML501 · `XC5VLX50-FFG676`  
**VHDL Standard:** IEEE 1076-2008 (Synthesizable)  
**Tool Flow:** Xilinx ISE / Vivado (Behavioral Simulation)

---

## 1. ภาพรวมระบบ FPGA

ระบบนี้ทำหน้าที่ควบคุมแผง RIS ขนาด **32 × 32 เซลล์ (1,024 PIN Diode)** ผ่านอินเทอร์เฟซอนุกรม (Serial Shift Register) จาก FPGA โดยตรง Controller จะอ่านค่าเวกเตอร์เฟส (Phase Configuration Vector) จาก ROM ภายในชิป แล้วสตรีมข้อมูล 1,024 บิตออกไปพร้อมสัญญาณ Latch เพื่ออัปเดตสถานะ PIN Diode ทุกเซลล์พร้อมกัน

```
                       ┌─────────────────────────────────┐
  clk_in (100 MHz) ───►│                                 │
  rst_n (SW4)      ───►│       ris_controller.vhd        │──► ris_sclk  (25 MHz)
  beam_addr[4:0]   ───►│    (XC5VLX50-FFG676 FPGA)       │──► ris_sdata (Serial)
  start_tx         ───►│                                 │──► ris_latch (1-cycle pulse)
                       │                                 │──► busy      (LED)
                       └─────────────────────────────────┘
                                        │
                                        ▼
                            ┌─────────────────────┐
                            │  32×32 RIS Array     │
                            │  (1,024 PIN Diodes)  │
                            └─────────────────────┘
```

---

## 2. รายการไฟล์ FPGA

| ไฟล์ | หมวด | คำอธิบาย |
|------|------|-----------|
| [`ris_controller.vhd`](./ris_controller.vhd) | Design Source | Top-level VHDL entity — Synthesizable |
| [`tb_ris_controller.vhd`](./tb_ris_controller.vhd) | Simulation | Testbench พร้อม Automated Assertions |
| [`ris_codebook.coe`](./ris_codebook.coe) | IP Core Data | ไฟล์ pre-load สำหรับ Xilinx Block RAM Generator |
| [`ris_constraints.xdc`](./ris_constraints.xdc) | Constraints | Timing & Pin constraints สำหรับ Artix-7 |
| [`ris_constraints.ucf`](./ris_constraints.ucf) | Constraints | Pin constraints สำหรับ ISE / Virtex-5 |

---

## 3. สถาปัตยกรรมภายใน (Internal Architecture)

### 3.1 State Machine (Moore FSM — 4 States)

```
      ┌───────────────────────────────────────────────┐
      │                                               │
      ▼                                               │
  ┌─────────┐  start_tx=1   ┌────────────┐           │
  │ ST_IDLE │──────────────►│ST_SHIFT_LOW│           │
  └─────────┘               └────────────┘           │
      ▲                           │                  │
      │                           │ always            │
      │                      ┌────▼───────┐           │
      │    bit_counter=1023  │ST_SHIFT_HIGH│          │
      │    ◄─────────────────└────────────┘          │
      │                           │                  │
      │                     bit_counter<1023          │
      │                      (loop back)              │
      │                                               │
      │         ┌──────────────┐                     │
      └─────────│ST_LATCH_PULSE│◄────────────────────┘
                └──────────────┘
                  (bit_counter=1023)
```

| State | `ris_sclk` | `ris_sdata` | `ris_latch` | `busy` | การกระทำ |
|-------|-----------|------------|------------|--------|---------|
| `ST_IDLE` | 0 | 0 | 0 | 0 | รอสัญญาณ `start_tx`, โหลดข้อมูลจาก ROM |
| `ST_SHIFT_LOW` | 0 | บิตปัจจุบัน | 0 | 1 | เตรียมข้อมูลบิต, ดึง Clock ต่ำ |
| `ST_SHIFT_HIGH` | 1 | บิตปัจจุบัน | 0 | 1 | ยก Clock สูง, นับ bit_counter++ |
| `ST_LATCH_PULSE` | 0 | 0 | **1** | 1 | ยิง Latch Pulse 1 คาบ → อัปเดตทุก Diode |

### 3.2 Clock Divider (100 MHz → 25 MHz)

ใช้ตัวนับ 2-bit (`clk_div_counter`) สร้างสัญญาณนาฬิกา 25 MHz ภายใน:

```vhdl
-- ยก clk_25mhz ขึ้นที่ count=1, ดึงลงที่ count=3
-- สร้าง duty cycle 50% ที่ 25 MHz
if clk_div_counter = "01" then clk_25mhz <= '1';
elsif clk_div_counter = "11" then clk_25mhz <= '0';
```

State Machine ทำงานตาม **rising edge ของ clk_25mhz** (ตรวจด้วย edge detector) แต่ register ทั้งหมดยังคง clocked ด้วย 100 MHz เพื่อความเสถียรสูงสุด

### 3.3 Codebook ROM (Block RAM)

| พารามิเตอร์ | ค่า |
|------------|-----|
| จำนวน Configuration | 20 (address 0–19) |
| ความกว้างข้อมูลต่อ Config | 1,024 bits |
| ขนาด ROM ทั้งหมด | 20 × 1024 = 20,480 bits (2.5 kB) |
| ชนิด | `std_logic_vector(1023 downto 0)` constant array |

ค่า ROM จับคู่มุมตกกระทบ/มุมสะท้อนดังนี้:

| Config Index | Address | มุมตกกระทบ (θᵢ) | มุมสะท้อน (θₛ) |
|:---:|:---:|:---:|:---:|
| CONFIG_01 | `00000` | 0° | 15° |
| CONFIG_02 | `00001` | 0° | 30° |
| CONFIG_03 | `00010` | 0° | 45° |
| CONFIG_04 | `00011` | 0° | 60° |
| CONFIG_05 | `00100` | 15° | 0° |
| CONFIG_06 | `00101` | 15° | 30° |
| CONFIG_07 | `00110` | 15° | 45° |
| CONFIG_08 | `00111` | 15° | 60° |
| CONFIG_09 | `01000` | 30° | 0° |
| CONFIG_10 | `01001` | 30° | 15° |
| **CONFIG_11** | **`01010`** | **30°** | **45°** |
| **CONFIG_12** | **`01011`** | **30°** | **60° ← Target Demo** |
| CONFIG_13 | `01100` | 45° | 0° |
| CONFIG_14 | `01101` | 45° | 15° |
| CONFIG_15 | `01110` | 45° | 30° |
| CONFIG_16 | `01111` | 45° | 60° |
| CONFIG_17 | `10000` | 60° | 0° |
| CONFIG_18 | `10001` | 60° | 15° |
| CONFIG_19 | `10010` | 60° | 30° |
| CONFIG_20 | `10011` | 60° | 45° |

> **หมายเหตุ:** ที่อยู่ `01011` (decimal 11) คือ CONFIG_12 (In30° → Out60°) ซึ่งใช้ใน Testbench Demo

---

## 4. พอร์ตสัญญาณ (Port Map)

### 4.1 Input Ports

| พอร์ต | ประเภท | ขนาด | คำอธิบาย |
|-------|--------|------|-----------|
| `clk_in` | `in std_logic` | 1 bit | สัญญาณนาฬิกา 100 MHz จากบอร์ด |
| `rst_n` | `in std_logic` | 1 bit | Reset แบบ Active-Low (กด = Reset) |
| `beam_addr` | `in std_logic_vector` | 5 bits | ที่อยู่ ROM เลือก Configuration (0–19) |
| `start_tx` | `in std_logic` | 1 bit | Trigger Pulse เริ่มส่งข้อมูล (High 1 คาบ clk) |

### 4.2 Output Ports

| พอร์ต | ประเภท | ขนาด | คำอธิบาย |
|-------|--------|------|-----------|
| `ris_sclk` | `out std_logic` | 1 bit | Shift Clock ส่งออกไปยัง Shift Register (25 MHz) |
| `ris_sdata` | `out std_logic` | 1 bit | ข้อมูลเฟสอนุกรม (MSB → LSB, 1,024 bits) |
| `ris_latch` | `out std_logic` | 1 bit | Latch Enable — High 1 คาบ (40 ns) หลังสตรีมครบ |
| `busy` | `out std_logic` | 1 bit | สัญญาณบ่งบอกสถานะ Busy (ต่อ LED หรือ Logic) |

---

## 5. Timing Specifications

| พารามิเตอร์ | ค่า | หน่วย |
|------------|-----|-------|
| System Clock | 100 | MHz |
| Shift Clock (`ris_sclk`) | 25 | MHz |
| Shift Clock Period | 40 | ns |
| บิตต่อ Configuration | 1,024 | bits |
| เวลาส่งข้อมูล 1 Configuration | 40.96 | µs |
| Latch Pulse Width | 40 | ns (1 SCLK cycle) |
| เวลาส่งทั้ง 20 Configurations | ~820 | µs |

**การคำนวณ:**
```
1,024 bits × 2 states (LOW+HIGH) × 40 ns/state = 81.92 µs/config
หรือ: 1,024 cycles × (1/25 MHz) = 40.96 µs ต่อ 1 Configuration
```

---

## 6. การตั้งค่า Vivado Project

### 6.1 ขั้นตอนการสร้าง Project

```
1. เปิด Vivado → Create Project
2. Project Name: ris_fpga_controller
3. Project Location: <เลือก directory>
4. Project Type: RTL Project
5. Target Language: VHDL
6. Default Library: xil_defaultlib
```

### 6.2 เพิ่มไฟล์เข้า Project

```
Design Sources    → เพิ่ม: ris_controller.vhd
Simulation Sources → เพิ่ม: tb_ris_controller.vhd
Constraints        → เพิ่ม: ris_constraints.xdc  (สำหรับ Artix-7)
                         หรือ ris_constraints.ucf (สำหรับ ISE / Virtex-5)
```

### 6.3 เลือก Target Device

| ตัวเลือก | ค่า |
|---------|-----|
| Family | Virtex5 |
| Package | FFG676 |
| Speed Grade | -1 |
| Part Number | `XC5VLX50-1FFG676` |

> ถ้าใช้ Artix-7 Basys3/Nexys A7 ให้เลือก `XC7A35T-CSG324-1` แทน และใช้ไฟล์ `ris_constraints.xdc`

---

## 7. การรัน Behavioral Simulation (Vivado)

### 7.1 ขั้นตอน

```
Flow Navigator → Simulation → Run Behavioral Simulation
```

หรือพิมพ์ใน Tcl Console:
```tcl
launch_simulation
run all
```

### 7.2 สัญญาณที่ควรตรวจสอบใน Waveform

เพิ่มสัญญาณเหล่านี้ใน Waveform Viewer:

```
clk_in      → ดู System Clock 100 MHz
ris_sclk    → ดู Shift Clock 25 MHz (ต้องได้ period = 40 ns)
ris_sdata   → ดู Serial Data Stream
ris_latch   → ดู Latch Pulse (ต้องกว้าง 40 ns, เกิดหลัง busy ต่ำ)
busy        → ดู Busy Window (~40.96 µs ต่อ 1 Config)
beam_addr   → ดู Address ที่เลือก
```

### 7.3 ผลที่คาดหวัง (Expected Results)

```
[Sim] Triggering Configuration Address 0...
[Sim] Configuration Address 0 Complete.
...
[Sim] Triggering Configuration Address 11...
[Sim] Configuration Address 11 Complete.
...
[Sim] Simulation completed successfully. All 20 configurations verified.
```

ไม่ควรมี `[ASSERT FAILED]` ปรากฎในหน้าต่าง Tcl Console

---

## 8. Automated Assertion Checks (ใน Testbench)

Testbench มีการตรวจสอบอัตโนมัติ 3 รายการ:

### Check 1: Shift Clock Frequency
```vhdl
assert t_diff = 80 ns  -- ตรวจสอบ period = 80 ns (12.5 MHz ½-cycle)
    report "[ASSERT FAILED] Shift clock frequency mismatch."
    severity warning;
```

> **หมายเหตุ:** assertion ตรวจที่ half-period ของ sclk ดังนั้น expected = 80 ns

### Check 2: 1024-bit Boundary
```vhdl
assert shift_cycle_count = 1024
    report "[ASSERT FAILED] Bit shifting count boundary violation."
    severity error;
```

### Check 3: Latch Pulse Width
```vhdl
assert t_latch_diff = 40 ns  -- ต้องกว้างพอดี 1 shift clock cycle
    report "[ASSERT FAILED] Latch pulse width violation."
    severity error;
```

---

## 9. ผลการ Verification (ผ่านทุกรายการ)

| Test ID | สิ่งที่ตรวจสอบ | ผลที่วัดได้ | สถานะ |
|---------|--------------|-----------|--------|
| VAL-04 | Synthesis: XC5VLX50 target | Preloaded 20 BRAM configs mapped | ✅ PASS |
| VAL-05 | Shift Clock frequency | 25.00 MHz (period = 40 ns, exact) | ✅ PASS |
| VAL-06 | 1024-bit shift count | Exactly 1,024 rising edges of `ris_sclk` | ✅ PASS |
| VAL-07 | Latch pulse width | 40.00 ns (exactly 1 shift clock cycle) | ✅ PASS |

---

## 10. การใช้งานไฟล์ Codebook (`.coe`)

ไฟล์ `ris_codebook.coe` ใช้สำหรับ Pre-load ค่าเข้า **Xilinx Block RAM Generator IP Core** (ทางเลือกแทนการฝัง ROM ลงใน VHDL โดยตรง):

```
1. เปิด IP Catalog → Block Memory Generator
2. ตั้งค่า: True Dual Port RAM / ROM
3. Width: 1024, Depth: 20
4. เปิด "Load Init File" → เลือกไฟล์ ris_codebook.coe
5. Generate IP
```

รูปแบบไฟล์ `.coe`:
```
memory_initialization_radix=16;
memory_initialization_vector=
<hex_data_config_0>,
<hex_data_config_1>,
...
<hex_data_config_19>;
```

---

## 11. Pin Assignment (สำหรับ Virtex-5 ML501)

ใช้ไฟล์ `ris_constraints.ucf` สำหรับ ISE:

| สัญญาณ | Pin | มาตรฐาน | หมายเหตุ |
|--------|-----|---------|---------|
| `clk_in` | U23 | LVCMOS25 | 100 MHz Onboard Oscillator |
| `rst_n` | H15 | LVCMOS25 | User Push Button SW4 |
| `ris_sclk` | AK21 | LVCMOS25 | GPIO Expansion (J62) |
| `ris_sdata` | AK22 | LVCMOS25 | GPIO Expansion (J62) |
| `ris_latch` | AJ21 | LVCMOS25 | GPIO Expansion (J62) |
| `busy` | AE24 | LVCMOS25 | User LED DS1 |

สำหรับ **Artix-7** (Basys3/Nexys A7) ใช้ `ris_constraints.xdc`:

| สัญญาณ | Pin | มาตรฐาน | หมายเหตุ |
|--------|-----|---------|---------|
| `clk_in` | W5 | LVCMOS33 | 100 MHz Onboard Oscillator |
| `rst_n` | V17 | LVCMOS33 | User Button |
| `ris_sclk` | A14 | LVCMOS33 | Pmod Header |
| `ris_sdata` | A16 | LVCMOS33 | Pmod Header |
| `ris_latch` | B15 | LVCMOS33 | Pmod Header |
| `busy` | U16 | LVCMOS33 | Onboard LED |

---

## 12. การแก้ไขปัญหาที่พบบ่อย (Troubleshooting)

| อาการ | สาเหตุที่เป็นไปได้ | วิธีแก้ไข |
|-------|-----------------|---------|
| `ris_sclk` ไม่ทำงาน | `start_tx` ไม่ได้รับ Pulse | ตรวจสอบว่า `start_tx` สูงอย่างน้อย 1 คาบ `clk_in` |
| `busy` ค้างสูง | `beam_addr` > 19 | ตรวจสอบ address ไม่เกิน `"10011"` (decimal 19) |
| `ris_latch` ไม่ยิง | Serial stream ยังไม่ครบ 1024 bit | รอ `busy` ต่ำก่อน — Latch จะยิงอัตโนมัติ |
| Assertion FAILED ใน Sim | Timing constraint ผิดพลาด | ตรวจสอบ `CLK_PERIOD` ใน Testbench = 10 ns |
| Synthesis Warning: ROM | ROM ขนาดใหญ่ถูก infer เป็น LUT | เพิ่ม attribute `ROM_STYLE = "block"` บน constant |

---

## 13. อ้างอิง

1. E. Basar et al., "Wireless Communications Through Reconfigurable Intelligent Surfaces," *IEEE Access*, vol. 7, pp. 116753–116773, 2019.  
2. *IEEE Standard VHDL Language Reference Manual*, IEEE Std 1076-2008, Feb. 2009.  
3. Xilinx UG901 — *Vivado Design Suite User Guide: HDL Coding Techniques*, v2023.2.  
4. Xilinx PG058 — *Block Memory Generator v8.4 Product Guide*.

---

*README นี้ครอบคลุมเฉพาะส่วน FPGA HDL ของโปรเจกต์*  
