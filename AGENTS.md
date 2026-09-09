# AGENTS.md - instrukcja dla agenta (Codex, Claude Code i inne)

To repo to wizard instalacji Rakazo na zabezpieczonym VPS. Jedyne źródło prawdy dla agenta:
**`.claude/commands/rakazo-setup.md`** - przeczytaj go w całości i prowadź użytkownika fazami
F0 -> F9 (plus opcjonalna F6b) dokładnie w tej kolejności, z testem zaliczenia po każdej fazie.

Zasady, których nie wolno złamać (pełna lista w wizardzie, sekcja "ZASADY BEZPIECZEŃSTWA"):

1. Nie dotykaj konfiguracji SSH ani firewalla poza otwarciem portów 80 i 443.
2. Nie wklejaj do czatu zawartości `.env` ani żadnych sekretów; klucze API wpisuje użytkownik sam.
3. `SIGNUP_ALLOWLIST` ma zostać puste; rejestrację zamykasz w `.env` I w bazie (Faza 5).
4. Caddyfile z Fazy 4c zawiera linię `uri path_regexp ... novnc/session ...` - to obejście buga
   Rakazo #832 (czarny pulpit bota). Nie pomijaj jej i nie "upraszczaj" Caddyfile.
5. Czekaj na wynik każdej komendy. Test fazy nie przeszedł -> STOP, pokaż output, zapytaj.

Audyt: `scripts/check.sh --before` przed instalacją, `scripts/check.sh` po. Audyt PO ma być
bez FAIL. Gdy pulpit bota nie działa: `INSTRUKCJA.md` sekcja "Coś poszło nie tak?", punkty 5 i 12,
oraz `scripts/unlock-computer.sh`.

Komendy z `sudo` na serwerze: zapisz skrypt do pliku lokalnie, `scp` na serwer, wykonaj przez
`ssh USER@IP "bash /tmp/plik.sh"`. Nie łącz faz w jedną komendę.
