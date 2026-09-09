#!/bin/bash
# =============================================================================
# unlock-computer.sh - zwalnia zawieszoną dzierżawę komputera bota w Rakazo
# =============================================================================
# Objaw: "Computer is busy" / "Ekran zajęty przez nowszą sesję" / czarny ekran,
#        a Recover computer i Reset computer odpowiadają "Computer is busy".
# Dwie przyczyny, obie obsłużone:
#  1. Sterowanie trzyma człowiek ("You have control") - Recover/Reset odmawiają,
#     dopóki controlHolder='user'. Najpierw oddaj sterowanie w panelu; jeśli
#     karta padła i wpis został, skrypt go zeruje.
#  2. Bug upstreamu (stan 2026-09): po "Take control" dzierżawa wykonania żyje
#     24 h i nie znika po zakończeniu zadania bota.
# Uruchomienie na serwerze:  bash unlock-computer.sh            (pokaż + zapytaj)
#                            bash unlock-computer.sh --yes      (bez pytania)
# Nie dotyka aktywnych zadań: usuwa tylko dzierżawy po zakończonych runach.
# =============================================================================
set -euo pipefail
DIR="${RAKAZO_DIR:-$HOME/rakazo}"
[[ -f "$DIR/.env" ]] || { echo "Brak $DIR/.env (ustaw RAKAZO_DIR)"; exit 1; }
PGUSER=$(grep -E '^POSTGRES_USER=' "$DIR/.env" | cut -d= -f2)
PGDB=$(grep -E '^POSTGRES_DB=' "$DIR/.env" | cut -d= -f2)
PGC=$(docker ps --format '{{.Names}}' | grep -E 'rakazo.*postgres' | head -1)
[[ -n "$PGC" ]] || { echo "Nie widzę kontenera postgres (docker ps)"; exit 1; }
psql() { docker exec -i "$PGC" psql -U "$PGUSER" -d "$PGDB" -Atc "$1"; }

echo "Dzierżawy komputerów (bot | wygasa | status zadania):"
ROWS=$(psql "select l.\"botId\", l.\"expiresAt\", r.status from computer_execution_leases l join runs r on r.id=l.\"runId\";")
[[ -n "$ROWS" ]] && echo "$ROWS" || echo "  (brak)"
STALE=$(psql "select count(*) from computer_execution_leases l join runs r on r.id=l.\"runId\" where r.status in ('completed','failed','cancelled');")
CTRL=$(psql "select count(*) from computers where \"controlHolder\"<>'none';")
echo "Zawieszone dzierżawy po zakończonych zadaniach: $STALE, przejęte sterowanie: $CTRL"
if [[ "$STALE" == "0" && "$CTRL" == "0" ]]; then echo "Nic do zwolnienia. Jeśli komputer nadal 'busy', zadanie bota naprawdę trwa - zatrzymaj je w panelu."; exit 0; fi
if [[ "${1:-}" != "--yes" ]]; then read -rp "Zwolnić? (tak/nie) [nie]: " OK; [[ "${OK:-nie}" == "tak" ]] || exit 0; fi
psql "delete from computer_execution_leases where \"runId\" in (select id from runs where status in ('completed','failed','cancelled'));" >/dev/null
psql "update computers set \"controlHolder\"='none', \"controlLeaseId\"=null, \"controlLeaseExpiresAt\"=null, \"controlBotId\"=null where \"controlHolder\"<>'none';" >/dev/null
echo "Zwolnione. Przeładuj panel (Cmd+Shift+R) i kliknij Open computer."
echo "Jeśli ekran nadal czarny: teraz Recover computer w panelu przejdzie. Ostateczność:"
docker ps --format '  docker stop {{.Names}}' | grep -E 'rakazo-bot' || echo "  (brak kontenera komputera bota)"
