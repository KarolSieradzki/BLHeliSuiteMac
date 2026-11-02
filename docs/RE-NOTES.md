# Reverse-engineering notes (BLHeliSuite 16.7.14.9.0.2)

Analysis with Ghidra 12.1.4 (headless and through the REA MCP server). Addresses refer to `BLHeliSuite.exe`
(Delphi 2007, EurekaLog 5.1.12), `SiUtil.dll` and `USBHID.dll` of the original Windows distribution.
The Swift sources quote these addresses in their comments (`FUN_00677AA4`, `0x64D2E0`, …) so every ported
function can be traced back to the original.

## Program structure

* Delphi RTTI (VMTs, published methods and fields) names every form class, its components (field offsets)
  and its event handlers. Handlers of the DFM files were mapped to addresses and decompiled; Delphi string
  literals, resource strings (`LoadResString`) and field offsets were annotated automatically.
* Forms and frames: `TfrmBLHeliSuiteMain`, `TfraESCCombos` (ESC setup page), `TfraESCTable` (ESC overview),
  `TfraCFMotorTest` / `TfraMotorControl` / `TfraAlternateSpeedTest` / `TfrmFCEnhTests` (Motors),
  `TfraMakeInterfaces` / `TfraSelectIspParams` / `TfraSetupArduinoUSBLinker` (Make interfaces),
  `TfrmFlashAssistant`, `TfrmConfirmFlash`, `TfrmMemoView`, `TfrmErasePageDlg`, `TfrmCompareResults`,
  `TfrmFuseEditor` / `TfraAVRFuses`, `TfrmLogForm`, `TfrmInfo`, `TAboutBox`, `TfrmInterfaceOptions`,
  `TfrmAvrISPSelectParams`, `TfrmSetupArduinoUSBLinker`.
* `TFRAEXPERTTOOLS`, `TFRMESCTABLE`, `TFRMESCCOMBOS` and the JVCL dialogs are resources without code in this
  version (no VMT) and are not used.
* `TBLHeli` (VMT 0x5A41F8) holds one ESC setup: parameter bytes, layout index (+0x20, valid when > 0),
  brand (+0x51), BLHeli_S flag (+0x52). Layout table records are 0x409 bytes (+0x102 BEC steps,
  +0x103 description, +0x408 LED count).
* Interface types (main form +0x799): 0 A … 4 E (SiLabs), 5 "1" … 10 "6", 11 X (Atmel), 12 none.

## VCL compatibility layer (`Sources/VCL`)

* `Tools/extract_vcl_resources.py` copies the PE resources: `Forms/*.dfm` (binary `TPF0` streams),
  `Bitmaps/*.bmp` (RT_BITMAP, e.g. the `BBOK`/`BBCANCEL` button glyphs), `RCData/*` (about box text, Atmel
  bootloader images) and `Strings.txt` (string table).
* `DFM.swift` reads `TPF0`, `Loader.swift` instantiates the component classes by name, assigns properties,
  binds outlets (`@objc var` fields) and events (`@objc func handler(_:)` selectors named in the DFM),
  resolves component references and inline frames.
* Controls draw themselves like Windows 10 VCL controls (Tahoma metrics, system colours, `TColor` BGR values);
  pixel coordinates of the DFM are used as macOS points.
* Delphi details kept: `TStringGrid.Objects`, owner drawing with `TCanvas`, `TJvStringGrid` alignment only
  without `OnDrawCell`, grid selection highlight while unfocused, `TAction` updates in idle time,
  `Application.OnIdle`, modal results, message dialogs with the Wingdings "save screenshot" button.

## Firmware database

* The hex files are resources of `BLHeliSilabsHex.dll` / `BLHeliAtmelHex.dll` (lists
  `BLHeliSilabsHexResList`, `BLHeliAtmelHexResList`). `Tools/build_firmware_db.py` extracts them into
  `Resources/FirmwareDB.bin`.
* Format `BLHFWDB2`: `metaRaw u32, metaLen u32` + JSON (zlib), then `blobRaw u32, blobLen u32` + image stream
  (zlib). Image = `seg_count` + segments `(addr u32, len u32, bytes)`.
* File record: `res, layout, mcu, family (1 SiLabs / 2 Atmel), isS, mode (0 MAIN / 1 TAIL / 2 MULTI), rev,
  layoutRev, defStartupPower, defStartupMethod, defSpoolup, revStr, name, extra`. `mcu` is the C2 device id
  for SiLabs (0x0A F33x, 0x08 F31x, 0x2B F39x, 0x30 F85x/EFM8BB1, 0x32 EFM8BB2) and the full signature for AVR
  (0x1E9307 ATmega8, 0x1E940B ATmega168).
* BLHeli_S layouts are generated like in the program: letters A…Z × H (48 MHz) / L (24 MHz) × dead time.

## ESC parameters (`BLHeliParams.swift`, `TBLHeli.swift`)

| Original | Port |
|---|---|
| `FUN_005AA830` – parameter exists for revision / mode | `BLHeliParamLogic.exists` |
| `FUN_005A6534` – exists, BEC / LED only if the layout has them | `TBLHeli.has` |
| `FUN_005A8564` – ranges | `BLHeliParamLogic.range` |
| `FUN_005A9324` – value texts | `BLHeliParamLogic.label` |
| `FUN_005AABF4` – default values | `BLHeliParamLogic.defaultValue` |
| `FUN_005A9C70` – parameter hints | `TfraESCCombos.hintText` |
| `FUN_005AB2F0` – display names ("Closed Loop P-Gain" …) | `BLHeliParam.displayName` |
| `TBLHeliTranslator` – settings between EEPROM revisions | `SettingsTranslator` |
| `FUN_0059BAA0` – ESC layout lookup | `FirmwareDatabase.layoutIndex` |

Setup block: 0x70 bytes (SiLabs: flash 0x1A00, Atmel: EEPROM 0). The mode is stored as A5/5A (MAIN),
5A/A5 (TAIL), 55/AA (MULTI); the firmware name `#BLHELI$` marks BLHeli_S.

## Main operations

* Read `FUN_00677AA4` with result messages `FUN_0065F29C` (unknown / locked / erased / outdated / removed /
  flash failed), write `FUN_0067910C` / `FUN_006789C4`, check `FUN_0067A2C4`, connect `FUN_00664538` /
  `FUN_0065E134`, interface mismatch `FUN_00677E4C`.
* Flash: `FUN_00665658` → Flash Assistant `FUN_00665B2C` / `FUN_0065572C` → SiLabs `FUN_0066AC14` or Atmel
  `FUN_00665FE0`, each with `TfrmConfirmFlash`. Times are `GetTickCount` differences / 1000.
* SiLabs with bootloader (`FUN_005DE5B8`): `**FLASH*FAILED**` marker in the setup block, `LJMP 0x1C00` at
  address 0 (the bootloader takes over if flashing is interrupted), erase/write pages 2…12, page 0, page 1,
  settings page, verify.
* Atmel with bootloader (`FUN_005DB468`): marker, jump to the bootloader (`DF CD` for 8 KB devices,
  `0C 94 00 1E` otherwise), contents, pages 0–1, EEPROM, verify.
* C2 (Arduino 4-way or ToolStick): chip erase, write non-empty blocks, optionally with bootloader.
* ESC overview (`TfraESCTable`, 0x64C768): one row per parameter present in any ESC (`FUN_0064D788`), Objects
  hold parameter index / value; values different from the master on `$FFEFA6`, non-default values bold.
  The edit combo box exists, but the editing flag (+0x278) is never set – the table is read only.

## Protocols

* MSP v1 (Betaflight): FC identification, armed check, `MSP_SET_4WAY_IF` (245) returns the ESC count.
* 4-way interface: commands 0x30…0x40, CRC16-XMODEM, the same protocol on flight controllers and Arduinos.
* BLHeli 1-wire bootloader (`TBootloader`, 0x5E3F70…): commands RUN 0, PROG_FLASH 1, ERASE 2, READ_SIL /
  VERIFY 3, READ_EE 4, PROG_EE 5, READ_SRAM 6, READ_ATM 7, KEEPALIVE FD, SET_BUFFER FE, SET_ADDRESS FF;
  ACK 0x30, errors 0xC0…0xC6; CRC16 poly 0xA001; boot info `"471" + x + sigHi + sigLo + version + pages`.
* SimonK bootloader: STK500v2; ArduinoUSBLinker (`$M<P/B/R/W`, `TArduinoUSBLinker` 0x61FA3C).
* Arduino boards: STK500v1 (optiboot) without avrdude; board table of `BLHeliSuite.exe` (27 boards);
  Mega 2560 (wiring) and Leonardo (avr109) through avrdude.
* ISP: avrdude (USBasp, ArduinoISP, …).

## ToolStick / USB Debug Adapter (`ToolstickProgrammer.swift`)

`USBHID.dll`:
* `EC3Write`: data split into 64-byte output reports, byte 0 (report id) = length (≤ 63).
* `EC3Read`: one 64-byte input report, result without byte 0.
* `TXFeatureReport(id, val)` / `RXFeatureReport(id)`: 2-byte feature reports.

`SiUtil.dll` (adapter type 3 = USB, C2 mode):
* Acknowledge: 0x0D = OK; 0x01, 0x02, 0x03, 0x57 = errors (`FUN_10001D30`).
* Initialisation (`FUN_100073F0`, `FUN_10005270`): feature 0x43 = mode, 0x41 → 0x42 (== 1) → 0x44 = firmware
  version (expected 0x12), otherwise 0x40, 1.
* Connect (`FUN_10006730`): `[0x40, option]`, `[0x20]`; disconnect `[0x21]`.
* Ids: `[0x22]` → (device id, revision), `[0x23]` → (derivative, …).
* Read code (`FUN_10003E00` → `FUN_100032D0`): `[0x2E, lo, hi, n ≤ 60]` → n bytes + status.
* Write code (`FUN_10003F00` → `FUN_10003520`): `[0x2F, lo, hi, n ≤ 60, data…]` → ack.
* Erase page `[0x30, page]`, erase device `[0x3C]` (up to 15 s).
* SFR access: `[0x36, addr, 1]` read, `[0x37, addr, 1, value]` write.
