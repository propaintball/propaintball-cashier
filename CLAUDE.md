# ProPaintball Pokladňa — Projektová dokumentácia

## Čo je to
Single-file PWA pokladničný systém (`propaintball-cashier.html`) pre ProPaintball areál v Bratislave.
Firma: TRESAERIS GROUP s.r.o., IČO: 50925989

## Technický stack
- Čistý HTML/JS/CSS, žiadne build nástroje
- localStorage ako primárny storage
- Supabase (voliteľný) pre cloud sync
- Chart.js + xlsx.js (CDN)
- PWA pre iOS iPad (hlavné zariadenie)

## Dev server
```
python3 /tmp/pb_serve.py  # port 8080
# súbor skopírovať do /tmp pred spustením (sandbox obmedzenie)
```
Konfig: `.claude/launch.json`

## Architektúra
- **Sessions (sessArr)**: aktívne hry, uložené v localStorage `pb_ss`
- **wbMap**: hráči per session (náramky/wristbands)
- **closed**: uzavreté účty
- **prods (DEF_P)**: produkty — balíky, ammo, extras, drinks, záloha

## Používatelia a roly
- **Admin** (heslo v `admPw`, default "admin123") — plný prístup
- **Inštruktor** — vlastné hry, heslo = meno_bez_diakritiky + "1" (napr. "michal1")
- Inštruktori: Michal Jacmenik, Marko, Joel, Michal Lupal, Peto, Zdenko, Maxo, Dominik

## Kľúčové funkcie
- `startSess()` — vytvorenie novej hry, ukladá `instructors: []` pole
- `closeBill()` → `checkDepositBeforeClose()` → `_proceedCloseBill()` — platobný tok
- `openCloseSess()` — uzavretie akcie, výpočet odmeny inštruktora
- `confirmCloseSess()` — uloží payout, exportuje XLS + JSON zálohu

## Formula odmeny inštruktora
```
hodinova_baza = 7 € × počet_hodín  (default 5 hodín = 35 €)
bonus = (tržba × 0.01) / počet_inštruktorov
odmena_per_instr = max(hodinova_baza + bonus, 35 €)
celkom = odmena_per_instr × počet_inštruktorov
```

## Záloha (Deposit) systém
- Pri prvom uzavretí účtu v session sa pýta "Bola uhradená záloha?"
- Záloha sa ukladá na `sess.deposit = {amount, scope, wbId}`
- **Záloha NEZNIŽUJE tržbu** (len zobrazí "Na inkaso" v platobnom okne)
- Produkt "Záloha" (id:35, cena:-50) je alternatíva — ZNIŽUJE účet

## Supabase sync
- Tabuľka: `pb_data` (id, payload jsonb, updated_at, backup_type, backup_label)
- Sync každé 4 sekundy po zmene (debounce)
- Automatické zálohy: týždenné (pondelok) + mesačné (1. v mesiaci), max 24

## Zmenené v tejto session (2026-04-09)
- Opravené bugy: duplikátny class atribút, hodinový interval (1s), _call() ochrana
- Záloha systém (popup + produkt)
- Viacerí inštruktori per session (instructors pole, spätná kompatibilita)
- Nová formula odmeny (7€/hod + 1% bonus)
- Offline indikátor

## Súbory
- `propaintball-cashier.html` — celá aplikácia (single-file)
- `serve.py` — Python HTTP server skript
- `.claude/launch.json` — dev server konfig
