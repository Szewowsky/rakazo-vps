# Rakazo na własnym VPS 🤖

Postaw sobie własny zespół agentów AI na serwerze, który już masz. Gotowy wizard dla Claude Code + przewodnik krok po kroku po polsku.

## Dla kogo?

Masz VPS z Ubuntu 24.04 (np. Hostinger, DigitalOcean, Hetzner), który jest **już zabezpieczony** - użytkownik nie-root, logowanie kluczem SSH, UFW, fail2ban. Chcesz na nim postawić Rakazo: boty z pamięcią, rutynami i własnym "komputerem" (kontener z pulpitem, przeglądarką i terminalem).

### Krok zero: najpierw zabezpiecz serwer

Ten poradnik **nie robi hardeningu**. Zakłada, że serwer jest już bezpieczny. Jeśli nie jest - zacznij tutaj:

**https://szewowsky.github.io/vps-security/**

Wróć, gdy audyt z tamtego repo świeci na zielono.

## Co dostajesz?

- **Wizard dla Claude Code** - 10 faz (F0-F9, plus opcjonalna F6b: aplikacje przez Composio), każda z komendą, oczekiwanym wynikiem, testem zaliczenia i planem B
- **Skrypt audytu** - `scripts/check.sh` sprawdza serwer PRZED i PO instalacji, PASS/WARN/FAIL per punkt
- **Instrukcja tekstowa** - `INSTRUKCJA.md` dla tych, którzy wolą kopiować komendy ręcznie

## Wymagania

| Co | Minimum |
|----|---------|
| System | Ubuntu 24.04 LTS |
| CPU | 2 vCPU |
| RAM | 4 GB (każdy aktywny bot-komputer zjada 1-2 GB) |
| Dysk | 10 GB wolnego |
| Porty | 80 i 443 wolne i przepuszczone przez UFW |
| Domena | subdomena z rekordem A na IP serwera (do HTTPS); bez własnej domeny wystarczy nazwa od hostingu, np. `srvNNNNNN.hstgr.cloud` |

## Quick Start

### Opcja A: Wklej jeden prompt agentowi (zalecane - tak robię to w filmie)

Otwórz Claude Code w nowym, pustym folderze i wklej to w całości:

```text
Sklonuj repozytorium https://github.com/Szewowsky/rakazo-vps.git do bieżącego katalogu,
przeczytaj plik .claude/commands/rakazo-setup.md i przeprowadź mnie przez opisany tam wizard
instalacji Rakazo na moim VPS - dokładnie według jego zasad bezpieczeństwa i kolejności faz
od F0 do F9. Idź krok po kroku: czekaj na wynik każdej komendy i nie przechodź dalej, jeśli
test fazy nie przeszedł. Zacznij od zebrania danych (Faza 0), potem audyt PRZED przez
scripts/check.sh --before, instalacja, audyt PO - i na końcu pokaż mi zestawienie: co było
na czerwono, a co jest teraz na zielono. Mój serwer jest już zabezpieczony poradnikiem
vps-security, więc NIE zmieniaj konfiguracji SSH ani reguł firewalla poza otwarciem portów
80 i 443. Komendy z sudo buduj heredokiem zapisywanym do pliku i uruchamianym przez ssh,
nie wpisuj sudo w komendzie inline. Nie ustawiaj SIGNUP_ALLOWLIST - ma zostać puste.
Nigdy nie wklejaj do czatu zawartości pliku .env.
```

Agent zapyta Cię o dane serwera i domenę, a potem poprowadzi przez całość.
Dokładna instrukcja krok po kroku (ze zrzutami i testami "czy zadziałało"): **[poradnik](https://szewowsky.github.io/rakazo-vps/)**.

### Opcja B: Z Claude Code, ręcznie przez slash command

```bash
git clone https://github.com/Szewowsky/rakazo-vps.git
cd rakazo-vps
claude
# wpisz: /rakazo-setup
```

### Opcja C: Ręcznie, bez agenta

Wszystkie komendy w tej samej kolejności znajdziesz w **[INSTRUKCJA.md](INSTRUKCJA.md)**.
Audyt serwera przed startem:

```bash
scp ./scripts/check.sh twoj_user@TWOJE_IP:/tmp/
ssh twoj_user@TWOJE_IP "bash /tmp/check.sh --before"
```

## 10 faz wizarda

| # | Faza | Test zaliczenia |
|---|------|-----------------|
| F0 | Dane: adres, użytkownik, port SSH, domena, e-mail | wszystkie pola zebrane, nic nie zgadywane |
| F1 | Test SSH i wymagania serwera | `check.sh --before` bez FAIL w sekcji wymagań |
| F2 | Docker Engine + Compose plugin | `docker compose version` działa bez sudo |
| F3 | Instalacja z obrazów GHCR + edycja `.env` | wszystkie kontenery `rakazo-*` running/healthy |
| F4 | TLS: Caddy + smoke test API | `https://twoja-domena/api/auth/ok` zwraca `{"ok":true}` |
| F5 | Pierwsze konto (owner) + zamknięcie rejestracji | drugi mail dostaje "Registration is closed" |
| F6 | Podpięcie modelu (OpenRouter albo OAuth) | bot odpowiada na wiadomość |
| F6b | Aplikacje przez Composio (opcjonalnie) | katalog się ładuje, jedna aplikacja Connected, bot zwraca prawdziwe dane |
| F7 | Test komputera bota | bot otwiera stronę w przeglądarce, widać pulpit |
| F8 | Pierwszy bot z rutyną | rutyna wykonuje się o czasie |
| F9 | Backup i aktualizacje | backup odtwarza się na czysto |

## Audyt

Nie wiesz, czy serwer jest gotowy albo czy instalacja wyszła? Uruchom audyt na serwerze:

```bash
bash check.sh --before   # przed instalacją: brak Dockera to WARN, nie FAIL
bash check.sh            # po instalacji: wszystko ma być zielone
```

Dostaniesz raport PASS/WARN/FAIL: wymagania sprzętowe, Docker, porty, kontenery, TLS, uprawnienia `.env`, stan rejestracji. Skrypt **niczego nie zmienia** - można go puszczać ile razy chcesz.

## Ważne

- **`SIGNUP_ALLOWLIST` zostaje puste** - niepusta allowlista wymusza weryfikację e-maila, a instalacja
  nie ma SMTP, więc nie zalogujesz się na własne konto. Zamiast tego: rejestracja otwarta na kilka
  minut (F5), konto ownera, natychmiast `SIGNUPS_ENABLED=false`
- **Nie zmieniamy SSH ani firewalla** poza otwarciem portów 80 i 443 - to zrobił za Ciebie vps-security
- **Sekrety generuje instalator** (`install-images.sh`) - nie wymyślasz ich sam, nie wklejasz do czatu
- **Nigdy nie wystawiaj portu 3100 ani 5173 na świat** - do internetu wychodzi tylko Caddy na 80/443
- **`ENCRYPTION_KEY` w `.env` jest nietykalny** - jego zmiana czyni zapisane hasła nie do odszyfrowania
- Skrypt audytu jest **idempotentny** - bezpieczny do wielokrotnego uruchomienia
- Testuj na świeżym VPS, zanim ruszysz produkcję

## Czym jest Rakazo

[Rakazo](https://github.com/elie222/rakazo) to open-source'owy projekt Elie Steinbocka (licencja Apache 2.0) - trwałe boty z pamięcią, rutynami i własnym komputerem w kontenerze. Model podpinasz swój. To repo **nie jest** częścią projektu Rakazo ani nie jest przez niego firmowane - to nieoficjalny poradnik instalacji po polsku, oparty na oficjalnej dokumentacji `docs/self-host.md` i obrazach GHCR.

## Licencja

MIT - patrz [LICENSE](LICENSE). Sam Rakazo jest na licencji Apache 2.0 i pozostaje własnością swoich autorów.

---

Materiał towarzyszący do filmu na YouTube. Kanał: [Robert Szewczyk](https://youtube.com/@robert_szewczyk)
