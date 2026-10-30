# BLHeliSuite dla macOS

Natywna aplikacja macOS (SwiftUI, Apple Silicon i Intel) odtworzona z BLHeliSuite 16.7.14.9.0.2 dla Windows.
Programuje ESC z firmware **BLHeli_S**, **BLHeli SiLabs** i **BLHeli Atmel**.

Gotowa aplikacja: `build/BLHeliSuite.app` (przeciągnij do „Programy” albo `./build_app.sh --install`).

## Wygląd

Domyślnie aplikacja wygląda jak oryginalny BLHeliSuite dla Windows:

* ten sam układ okna – pozycje i rozmiary kontrolek wzięte z formularzy Delphi (DFM) w `BLHeliSuite.exe`,
* ramki parametrów z wartością na niebieskim tle, zielonym „LED-em” z surową wartością, paskiem przewijania
  oraz przyciskami Undo / Default,
* oryginalne ikony przycisków, obrazki płytek i skrzynek programujących (wyciągnięte z EXE),
* menu „Select ATMEL / SILABS Interface” z kolorowymi literami interfejsów (A–E, 1–6, X),
* grupa „Multiple ESC / Master#1” (niebieski master, zielone zsynchronizowane, pomarańczowe – inny kierunek…),
* okno „Logged Messages” (Options → Enable Log), „Save Screenshot” w menu.

Nowoczesny układ macOS: menu **Options → Modern macOS look** albo **View → Classic BLHeliSuite Look** (⇧⌘L) –
przełącza w obie strony. Grafiki generuje `Tools/make_classic_assets.py` z oryginalnego `BLHeliSuite.exe`.

## Obsługiwane interfejsy (menu *Interface*)

| Interfejs | Opis |
|---|---|
| SILABS / ATMEL … (Betaflight/Cleanflight) | ESC podłączone do kontrolera lotu (Betaflight, Cleanflight, INAV, EmuFlight). Port USB kontrolera, 115200. Kontroler musi być **rozbrojony**, ESC zasilone z baterii. |
| SILABS BLHeli Bootloader (4way-if) / ATMEL … (4way-if) | Arduino z firmware 4-way (zakładka *Make Interfaces*), 38400 baud. |
| SILABS C2 (4way-if) | Arduino 4-way w trybie C2 – programowanie ESC bez bootloadera (C2CK → D11, C2D → D12). |
| SILABS C2 (Toolstick) | SiLabs ToolStick / USB Debug Adapter przez USB HID. |
| ATMEL ISP Interface (AVRDude / USBasp) | Programator ISP (USBasp, Arduino as ISP, …) – wymaga `brew install avrdude`. |

## Funkcje

* **Read Setup / Write Setup** – wszystkie parametry BLHeli z zakresami, etykietami i wartościami domyślnymi
  odtworzonymi z BLHeliSuite (zależnie od rewizji EEPROM, trybu MAIN/TAIL/MULTI, układu ESC).
* **Tryb wielu ESC** – przyciski 1–8, *Check*, Master/Slave, synchronizacja kierunku i zakresu throttle
  (menu *Options*), oznaczenia stanów (u, f, b, m), *Copy/Paste* ustawień.
* **Flash BLHeli** – wbudowana baza 8881 plików firmware (6933 SiLabs, 1948 Atmel, 774 układy ESC) z oryginalnych DLL.
  Ustawienia ESC są przenoszone na nową rewizję (port translatora z BLHeliSuite).
  Procedura flashowania jak w oryginale (skok do bootloadera na czas flashowania, znacznik `**FLASH*FAILED**`,
  weryfikacja).
* **Flash Other** – dowolny plik `.hex` (dla Atmel automatycznie dobierany `.eep`).
* **ESC Overview** – tabela wszystkich ESC.
* **Motors** – test silników przez MSP (zdejmij śmigła!).
* **Make Interfaces** – wgrywanie firmware 4-way / 1-wire / USBLinker / ArduinoISP na Arduino
  (Uno, Nano, Pro Mini… bezpośrednio przez bootloader; Mega/Leonardo przez avrdude).
* **Expert Tools** (menu *Options → Expert Mode*) – odczyt/zapis pamięci, kasowanie stron, zrzut flash do HEX.
* Zapis/odczyt ustawień do pliku `.ini`, log z podglądem ruchu protokołu.

## Budowanie i aktualizacja po zmianach w kodzie

Wystarczą Command Line Tools (`xcode-select --install`), Xcode nie jest potrzebny.

Kliknij dwukrotnie **`Aktualizuj BLHeliSuite.command`** w Finderze albo uruchom w terminalu `./build_app.sh`.
Skrypt:

1. kompiluje wszystko w trybie release (pełny log: `build/build.log`),
2. uruchamia testy `blheli-selftest` (`build/selftest.log`),
3. składa i podpisuje nową aplikację i dopiero gdy wszystko się uda, podmienia `build/BLHeliSuite.app`
   oraz kopię w `/Applications` lub `~/Applications`, jeśli tam jest,
4. zachowuje poprzednią wersję w `build/.previous/`.

Przy błędzie kompilacji albo testów stara aplikacja zostaje bez zmian.

| Opcja `build_app.sh` | Działanie |
|---|---|
| `--no-tests` | bez testów (szybciej) |
| `--install` | zainstaluj też w `/Applications` |
| `--open` | uruchom aplikację po zbudowaniu |
| `--rollback` | wróć do poprzedniej wersji (ponownie: z powrotem do nowszej) |

Numer kompilacji (data i godzina) jest widoczny w oknie *About BLHeliSuite*.
Przy pierwszym dwukliku macOS może zapytać, czy Terminal może korzystać z folderu Dokumenty – trzeba zezwolić.

Wersja debug do testów: `swift build`, potem `.build/debug/blheli-selftest`.

Baza firmware (`Resources/FirmwareDB.bin`) jest generowana z oryginalnych plików Windows:
`python3 Tools/build_firmware_db.py ../BLHeliSuite Resources/FirmwareDB.bin`.

## Narzędzia dodatkowe

* `blheli-cli` – wiersz poleceń: `ports`, `db`, `read`, `set`, `flash` (np. `blheli-cli read --port /dev/cu.usbmodem1101`).
* `blheli-sim` – symulator kontrolera lotu / Arduino 4-way z wirtualnymi ESC na pseudo-terminalu
  (np. `blheli-sim --escs 4`, potem w aplikacji wybierz wypisany port `/dev/ttys…`).
* Testy okna z symulatorem (po zmianach w interfejsie):
  * `BLHeliSuite --uitest /dev/ttys… --out <folder>` – klika myszą po klasycznym oknie (menu, listy,
    przyciski ESC, zakładki, ramki parametrów, Write Setup, okno flashowania, Motors); wynik w `uitest.json`,
  * `BLHeliSuite --autotest /dev/ttys… --out <folder> --interface E --style classic` – połączenie, zapis
    ustawień i flashowanie (`report.json` + zrzuty okna).

  Ustawienia użytkownika (interfejs, port, wygląd) są po teście przywracane.

## Uwagi

* Wszystko jest przetestowane na symulatorze; obsługa **Toolsticka** (USB HID) i **ISP** (avrdude) jest
  odtworzona z SiUtil.dll / BLHeliSuite, ale nie była sprawdzona na fizycznym sprzęcie.
* ESC z BLHeli_32 / AM32 (ARM) nie są obsługiwane – tak jak w oryginalnym BLHeliSuite.
* Aplikacja jest podpisana tylko lokalnie (ad-hoc). Na tym Macu uruchamia się normalnie; skopiowana na inny
  Mac (AirDrop, pobranie) zostanie przy pierwszym uruchomieniu zablokowana – wtedy *Ustawienia systemowe →
  Prywatność i ochrona → Otwórz mimo to* (albo zbuduj ją tam skryptem `build_app.sh`).
* Notatki z inżynierii wstecznej: `docs/RE-NOTES.md`.
