# Notatki z inżynierii wstecznej (BLHeliSuite 16.7.14.9.0.2)

Analiza: Ghidra 12.1.4 przez REA MCP. Adresy dotyczą `BLHeliSuite.exe`, `SiUtil.dll`, `USBHID.dll`
z folderu `../BLHeliSuite`.

## Baza firmware

* Pliki HEX są zasobami w DLL-ach dostarczanych z BLHeliSuite (listy `BLHeliSilabsHexResList`,
  `BLHeliAtmelHexResList`). `Tools/build_firmware_db.py` wyciąga je do `Resources/FirmwareDB.bin`.
* Format `BLHFWDB2`: `metaRaw u32, metaLen u32` + JSON (zlib), potem `blobRaw u32, blobLen u32` + strumień obrazów
  (zlib). Obraz = `seg_count` + segmenty `(addr u32, len u32, bytes)`.
* Rekord pliku: `res, layout, mcu, family (1 SiLabs / 2 Atmel), isS, mode (0 MAIN / 1 TAIL / 2 MULTI), rev,
  layoutRev, defStartupPower, defStartupMethod, defSpoolup, revStr, name, extra`.
  `mcu` = identyfikator C2 dla SiLabs (0x0A F33x, 0x08 F31x, 0x2B F39x, 0x30 F85x/EFM8BB1, 0x32 EFM8BB2),
  pełna sygnatura dla AVR (0x1E9307 ATmega8, 0x1E940B ATmega168).
* Układy BLHeli_S są generowane jak w programie: litery A…Z × H (48 MHz) / L (24 MHz) × deadtime.

## Parametry ESC (`BLHeliParams.swift`)

| Oryginał | Port |
|---|---|
| `FUN_005aa830` – czy parametr istnieje dla rewizji/trybu | `BLHeliParamLogic.exists` |
| `FUN_005a8564` – zakresy | `BLHeliParamLogic.range` |
| `FUN_005a9324` – etykiety wartości | `BLHeliParamLogic.label` |
| `FUN_005aabf4` – wartości domyślne | `BLHeliParamLogic.defaultValue` |
| `TBLHeliTranslator` – przenoszenie ustawień między rewizjami | `SettingsTranslator` |
| `FUN_0059baa0` – wyszukiwanie układu ESC | `FirmwareDatabase.layoutIndex` |

Blok ustawień: 0x70 bajtów (SiLabs: flash 0x1A00, Atmel: EEPROM 0). Tryb zapisany jako A5/5A (MAIN), 5A/A5 (TAIL),
55/AA (MULTI); nazwa firmware `#BLHELI$` oznacza BLHeli_S.

## Flashowanie (`ESCOperations.swift`)

* SiLabs z bootloaderem (`FUN_005de5b8`): znacznik `**FLASH*FAILED**` w bloku ustawień, `LJMP 0x1C00` na adresie 0
  (bootloader przejmuje start, jeśli flash zostanie przerwany), kasowanie i zapis stron 2…12, strona 0, strona 1,
  strona ustawień, weryfikacja.
* Atmel z bootloaderem (`FUN_005db468`): znacznik, skok do bootloadera (`DF CD` dla 8 KB, `0C 94 00 1E` w innych),
  zapis treści, stron 0–1, EEPROM, weryfikacja.
* C2 (Arduino 4-way lub Toolstick): kasowanie całego układu, zapis niepustych bloków, opcjonalnie z bootloaderem.

## Protokoły

* MSP v1 (Betaflight): identyfikacja FC, sprawdzenie uzbrojenia, `MSP_SET_4WAY_IF` (245) zwraca liczbę ESC.
* 4-way interface: komendy 0x30…0x40, CRC16-XMODEM, ten sam protokół dla FC i Arduino (38400).
* Arduino: STK500 v1 (optiboot) bez avrdude; tabela płytek z `BLHeliSuite.exe` @ 0x68FB44.
* ISP: avrdude (USBasp, ArduinoISP, …).

## ToolStick / USB Debug Adapter (`ToolstickProgrammer.swift`)

`USBHID.dll`:
* `EC3Write`: dane dzielone na raporty wyjściowe 64 B, bajt 0 (report id) = długość (≤ 63).
* `EC3Read`: jeden raport wejściowy 64 B, wynik bez bajtu 0.
* `TXFeatureReport(id, val)` / `RXFeatureReport(id)`: 2-bajtowe raporty feature.

`SiUtil.dll` (adapter typu 3 = USB, tryb C2):
* Potwierdzenie: 0x0D = OK; 0x01, 0x02, 0x03, 0x57 = błędy (`FUN_10001d30`).
* Inicjalizacja (`FUN_100073f0`, `FUN_10005270`): feature 0x43 = tryb, 0x41 → 0x42 (==1) → 0x44 = wersja firmware
  (oczekiwana 0x12), inaczej 0x40,1.
* Połączenie z celem (`FUN_10006730`): `[0x40, opcja]`, `[0x20]`; rozłączenie `[0x21]`.
* ID: `[0x22]` → (device id, rev), `[0x23]` → (derivative, …).
* Odczyt kodu (`FUN_10003e00` → `FUN_100032d0`): `[0x2E, lo, hi, n≤60]` → n bajtów + status.
* Zapis kodu (`FUN_10003f00` → `FUN_10003520`): `[0x2F, lo, hi, n≤60, dane…]` → ack.
* Kasowanie strony `[0x30, strona]`, kasowanie całości `[0x3C]` (do 15 s).
* Rejestry SFR: `[0x36, adr, 1]` odczyt, `[0x37, adr, 1, wartość]` zapis (zapis/odtworzenie SFRPAGE tylko dla
  rodzin 0x20/0x2A, nieużywanych w ESC).

Toolstick i ISP nie były testowane na fizycznym sprzęcie – tylko na symulatorze (`SimulatedToolstick`).

## Klasyczny interfejs (`Sources/BLHeliSuiteApp/Classic/`)

* Formularze Delphi to zasoby RCDATA (`TFRMBLHELISUITEMAIN`, `TFRAESCCOMBOS`, `TFRAMAKEINTERFACES`, …) w formacie
  binarnym `TPF0`. Pozycje (`Left/Top/Width/Height`), czcionki (Tahoma 11/12/13, Courier New dla „LED-ów”) i kolory
  przeniesione 1:1 (piksele Windows = punkty macOS). Okno główne: 778 × 582 + menu.
* Zakładka ustawień (`TfraESCCombos`): ramki 185 × 56 w siatce x = 4/195/385/575, y = 10 + 58·n. Wykluczające się
  parametry dzielą miejsce (np. Motor Gain / Governor Mode, Demag / Voltage Comp.); program tylko je pokazuje
  lub ukrywa. W ramce: `lbl_` (wartość, tło `#B0D8FF`), `led_` (surowa wartość, Courier New 28/19 pt, `clLime` na
  `clGray`, `RoundedFrame` 2), `scb_` (TScrollBar), `sbtnUNDO_` / `sbtnDEFAULT_`.
* Grafiki: `Glyph.Data` = u32 rozmiar + BMP (16×16, przezroczysty kolor = lewy dolny piksel), `Picture.Data` =
  nazwa klasy (`TBitmap`) + u32 + BMP, `TImageList.Bitmap` = strumień `IL` (comctl32) z kafelkami 16×16,
  przyciski `Kind=bkOK` itd. = zasoby RT_BITMAP `BBOK`, `BBCANCEL`, `BBIGNORE`.
  Generator: `Tools/make_classic_assets.py BLHeliSuite.exe Sources/BLHeliSuiteApp/Classic/ClassicAssets.swift`.
* Kolory odczytane ze zrzutów w instrukcjach PDF (Windows 8): tło ramek białe, ramka `#DCDCDC`, przyciski
  `#E1E1E1`/`#ADADAD`, interfejsy SiLabs `#FFFF80`/`#7E1245`, Atmel `#D3E5F8`/niebieski.
