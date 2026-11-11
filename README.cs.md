# Tablet

[English](README.md) · **Čeština**

Nativní aplikace pro macOS, která vrací do života grafický tablet **Wacom Intuos Pro M (PTH-651)**
na nových verzích macOS, pro které už Wacom ovladač nevydává. V základní podobě funguje i s dalšími tablety,
které podporuje OpenTabletDriver.

## Instalace

Stáhněte `Tablet-x.y.dmg` z [Releases](https://github.com/zdkdsgn/tablet/releases), přetáhněte Tablet do Aplikací
a při prvním spuštění povolte v **Nastavení systému → Soukromí a zabezpečení** „Přesto otevřít“
(aplikace není notarizovaná u Applu). Pak povolte **Zpřístupnění** a **Sledování vstupu**.

![ikona](Resources/icon.png)

## Jak to funguje

- Pero a ExpressKeys obsluhuje démon **OpenTabletDriveru**, který je **přibalený přímo v aplikaci**
  (`Tablet.app/Contents/Helpers/OpenTabletDriver.Daemon`). Samostatný OpenTabletDriver instalovat nemusíte.
  Pokud ho máte, Tablet jeho démona při startu zastaví a spustí svůj, aby s tabletem mluvil jen jeden ovladač.
- **Tablet** nahrazuje okno OpenTabletDriveru: zapisuje do `settings.json`
  (`~/Library/Application Support/OpenTabletDriver`) a démonovi ho rovnou předá přes jeho JSON-RPC socket
  (`$TMPDIR/CoreFxPipe_OpenTabletDriver.Daemon`, metoda `SetSettings`).
- Touch Ring, jeho tlačítko a světýlka obsluhuje Tablet přímo přes IOKit HID. Zařízení si nezabírá,
  takže OpenTabletDriver běží dál.

## Co umí

- **Tablet:** kresba tabletu s popisky. ExpressKeys mají zkratky nahrávané stiskem kláves (fyzické klávesy,
  takže fungují s jakoukoli klávesnicí, třeba s českou QWERTZ), kliknutí myší a vlastní názvy.
  Volitelně se při stisku ukáže oznámení na obrazovce. Místo zkratky můžou mít **funkci aplikace**:
  - **Přesný režim:** dokud tlačítko držíte, pero se pohybuje jemněji.
  - **Další monitor:** přepne mapování tabletu na další obrazovku.
  - **Kruhové menu:** podržíte tlačítko, perem vyberete jednu z 8 akcí a tlačítko pustíte.
- **Touch Ring:** plynulý zoom ke kurzoru (jemné posouvání s ⌥ nebo ⌘ podle aplikace). Tlačítko uprostřed přepíná
  vybrané režimy (nejvýš 4, podle počtu světýlek): Zoom, Velikost štětce, Historie, Posouvání
  a Otáčení plátna (Photoshop).
- **Světla:** světýlka kolečka a rohová světýlka plochy (jas, zapnutí a vypnutí, dýchání) a animace.
  Easter egg odemkne podržení tlačítka uprostřed kolečka.
- **Pero:** **křivka tlaku** (graf s tažitelným bodem, předvolby Měkký, Lineární a Tvrdý, „plný tlak při“),
  **vyhlazení tahu**, nastavení přesného režimu, zkušební plocha s ukazatelem tlaku, práh hrotu, vypnutí tlaku
  nebo náklonu a tlačítka pera i guma. Křivku, vyhlazení a přesný režim aplikuje Tablet na události pera
  od ovladače (event tap), takže fungují v každé aplikaci.
- **Okraje obrazovky:** kurzor pera zůstane uvnitř obrazovky a na okraji „tlačí“ ven, takže se automaticky
  skrytý Dock vysune i perem.
- **Plocha a monitor:** výběr monitoru, plocha tabletu posouvaná tažením, zachování poměru stran a režim pro leváky.
- **Předvolby:** uložená nastavení a automatické přepínání podle aplikace, která je vpředu. Spouštění po přihlášení.
- **Dotyk:** gesta jako na trackpadu. Je hotové, ale na testovaném kusu tabletu dotyková vrstva neposílá data,
  takže to není ověřené.
- **Express View:** lehké položení prstu na ExpressKeys ukáže u okraje obrazovky, co všechna tlačítka dělají
  (dotyk tlačítek hlásí bajt 5 zprávy podložky).
- **Dotyková tlačítka:** přejetí prstem po čtveřici ExpressKeys funguje jako posuvník (velikost štětce,
  historie, zoom, posouvání, vlastní zkratky). Světla můžou v klidu zhasnout a rozsvítit se až při dotyku.
- **Ikona v liště:** stav připojení, režim kolečka, předvolby a rychlé přepínače.
- **Kontrola ovladače:** jednou denně se podívá, jestli nevyšla novější verze OpenTabletDriveru.
- **Ťuknutí / podržení a kombinace:** ExpressKey pošle při ťuknutí jednu zkratku a při podržení drží jiné klávesy
  (⌥ pro kapátko, mezerník pro ruku). Dvě taková tlačítka stisknutá zároveň pošlou třetí zkratku.
- **Přepínání gumy:** otočíte pero a aplikace dostane klávesu gumy, otočíte zpět a dostane klávesu štětce.
- **Plocha na okno:** tlačítkem, v liště nebo zkratkou namapujete tablet jen na okno vpředu, znovu = celá obrazovka.
- **Kde kreslíte:** tepelná mapa tahů na ploše tabletu a návrh menší, přesnější plochy.
- **Kolečko podle aplikace, hlasitost, jas, zrychlení:** režim kolečka se přepíná podle aplikace vpředu, nové režimy
  pro hlasitost a jas, rychlé otočení dělá větší kroky.
- **Upozornění světly a přestávky:** světla bliknou při slabé baterii, po dlouhém kreslení (počítá se jen čas s perem
  v ruce) nebo když cokoli pošle `tablet://notify?title=…`.
- **Zkratky, Siri a Ovládací centrum:** akce aplikace (režim kolečka, přesný režim, plocha na okno, bliknutí světel)
  jsou v aplikaci Zkratky a odkazy `tablet://` fungují odkudkoli (`open -g tablet://ring/brush`). Ovládací prvky
  pro Ovládací centrum a lištu na macOS 26+.
- **Záloha:** všechno nastavení a předvolby v jednom souboru `.tabletsettings`.
- **Aktualizace:** Tablet se podívá do GitHub Releases, ověří SHA-256 DMG a sám se nahradí.
- **Rozpoznání pera a nastavení pro každé pero:** každé pero se pozná podle sériového čísla a může mít vlastní
  křivku tlaku, tlačítka i citlivost klepnutí.
- **Citlivost klepnutí a klidné klepnutí:** posuvník prahu hrotu s živým ukazatelem posledního ťuknutí a klidné
  klepnutí, kdy kurzor po dotyku hrotu chvilku stojí, takže ťuknutí klikne a netáhne.
- **Výřez MacBooku:** živý náklon pera z boku i shora, dokud je pero nad tabletem, statistiky po najetí perem do
  výřezu, milníky a úspěchy.
- **Tachometr a úspěchy:** kolik pero ujelo dnes a celkem, s vtipnými přirovnáními a 22 úspěchy (některé tajné).
- **Tahy:** všechny dnešní tahy na bílém papíře, s přehráním, barvami podle času a uložením do PNG (drží se 30 dní).
- **Bezdrátová sada:** stav baterie v postranním panelu a v liště, upozornění při 15 % a 5 % a při nabíjení,
  a úspora baterie, kdy světla zhasnou po 30 s bez práce.
- **Dotyk:** velikost doteku, poznání dlaně podle velikosti a boční vypínač dotyku.
- **Plocha a monitor:** náhledy zařízení s živou tečkou pera, skutečná velikost 1:1, posun šipkami a ⌘Z.
- **Vzhled:** světlý, tmavý, nebo podle macOS.
- **Průvodce nastavením:** oprávnění, monitor a citlivost pera krok za krokem při prvním spuštění (Obecné →
  Průvodce nastavením, nebo `tablet://setup`).
- **Nápověda a diagnostika:** nápověda v aplikaci (⌘?) s tipy, zkratkami a odkazy `tablet://`; „Uložit diagnostiku…“
  sbalí logy, nastavení ovladače a stav aplikace do jednoho .zip pro hlášení chyby (nic se neodesílá).
- **Homebrew:** `brew install --cask zdkdsgn/tap/tablet` (cask v `Casks/tablet.rb`).
- **Jazyk:** čeština a angličtina podle jazyka macOS. Překlady jsou v `Resources/en.lproj`
  a generuje je skript `Resources/translations-en.py`.

### Podporované tablety

| Úroveň | Tablety | Funkce |
|---|---|---|
| Rozšířená | Intuos Pro 2013 (PTH-451/651/851), Intuos5 (PTK-450/650/850, PTH-450/650/850) | všechno výše |
| Základní | ostatní tablety podporované OpenTabletDriverem | pero, křivka tlaku, vyhlazení, plocha, monitor, ExpressKeys a kolečko přes OpenTabletDriver, předvolby |

Ověřené je to jen s PTH-651. Hlášení o dalších tabletech jsou vítaná.

## Sestavení

Potřebujete macOS 14 nebo novější a Xcode (nebo Command Line Tools se Swiftem 5.10 a novějším).

```bash
./make-app.sh            # stáhne a ověří OpenTabletDriver (jen poprvé) a sestaví build/Tablet.app
./make-app.sh --install  # a zkopíruje ji do /Applications
./make-dmg.sh            # instalační build/Tablet-<verze>.dmg
```

Aplikace je podepsaná ad hoc, s požadavkem na podpis vázaným jen na identifikátor balíčku. Díky tomu si macOS
pamatuje udělená oprávnění i po novém sestavení. Identifikátor si můžete změnit v `make-app.sh`.

`swift test` spustí testy (dekódování zpráv z tabletu na skutečných datech, soubory tahů a ťuků, porovnání verzí,
křivka tlaku a kontrola, že každý český text má anglický překlad). `make-dmg.sh` sestaví vydání, jen když projdou.
Anglické texty se při každém sestavení generují z `Resources/translations-en.py`.

### Podpis a notarizace (volitelné)

S účtem Apple Developer jde aplikaci podepsat Developer ID a notarizovat, takže se otevře bez „Přesto otevřít“:

```bash
xcrun notarytool store-credentials tablet-notary --apple-id vy@example.com --team-id TEAMID   # jednou
SIGN_IDENTITY="Developer ID Application: Jméno (TEAMID)" NOTARY_PROFILE=tablet-notary ./make-dmg.sh
```

Ovladač se podepíše s hardened runtime a oprávněními pro JIT, která .NET potřebuje. Bez `SIGN_IDENTITY` zůstává
sestavení ad hoc jako dosud.

### Oprávnění (Nastavení systému → Soukromí a zabezpečení)

- **Zpřístupnění:** posílání událostí (zoom, klávesy, kurzor).
- **Sledování vstupu:** čtení kolečka, tlačítek a dotyku z tabletu.

## Poznámky k hardwaru (PTH-651, USB 056A:0315)

- Zprávy podložky (report ID 3, rozhraní pera 0xFF0D): bajt 2 = Touch Ring (bit 7 = prst na kolečku,
  hodnoty 0–71), bajt 3 bit 0 = tlačítko uprostřed, bajt 4 = ExpressKeys.
- Světýlka: feature report `0x20`, bajt 1 = `jas_rohů << 4 | jas_kolečka << 2 | světýlko`. Jas 0 je slabě,
  1 středně, 2 jasně a 3 vypnuto. Stejně to dělá ovladač `wacom` v Linuxu.
- Dotyk: rozhraní 0xFF00, 64bajtové zprávy (report ID 2).

## Licence

Kód aplikace je pod licencí MIT. [OpenTabletDriver](https://github.com/OpenTabletDriver/OpenTabletDriver) je samostatný projekt
pod licencí LGPL-3.0. Repozitář ho neobsahuje: `make-app.sh` stáhne jeho oficiální vydání (verze a SHA-256
jsou uvedené ve skriptu) a přibalí do aplikace nezměněný démon spolu s jeho licencí
(`Contents/Resources/OpenTabletDriver-LICENSE.txt`). Démona jde kdykoli nahradit jinou verzí.
