#!/bin/bash
# =============================================================================
# Audyt serwera pod Rakazo (PRZED i PO instalacji)
# =============================================================================
# Sprawdza, czy serwer nadaje się pod Rakazo i czy instalacja wyszła poprawnie.
# NICZEGO NIE ZMIENIA - można uruchamiać ile razy chcesz.
#
# Uruchom na serwerze:  bash check.sh
# Audyt PRZED instalacją:  bash check.sh --before
# Niektóre punkty (UFW, porty z PID) wymagają sudo - bez niego dostaniesz WARN.
# =============================================================================

set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

pass() { echo -e "  ${GREEN}[PASS]${NC}  $1"; PASS=$((PASS + 1)); }
fail() { echo -e "  ${RED}[FAIL]${NC}  $1"; FAIL=$((FAIL + 1)); }
warn() { echo -e "  ${YELLOW}[WARN]${NC}  $1"; WARN=$((WARN + 1)); }
header() { echo -e "\n${BLUE}━━━ $1 ━━━${NC}"; }

# Katalog instalacji Rakazo - można nadpisać: RAKAZO_DIR=/opt/rakazo bash check.sh
RAKAZO_DIR="${RAKAZO_DIR:-$HOME/rakazo}"

# Tryb audytu PRZED instalacją: brak Dockera i brak .env to wtedy stan oczekiwany,
# a nie awaria. Wymuszany flagą --before, rozpoznawany też automatycznie.
BEFORE=0
for arg in "$@"; do
    case "$arg" in
        --before) BEFORE=1 ;;
        --after)  BEFORE=0 ;;
    esac
done
if [[ "$BEFORE" -eq 0 ]] \
    && ! command -v docker >/dev/null 2>&1 \
    && [[ ! -f "$RAKAZO_DIR/.env" ]]; then
    BEFORE=1
fi

# W trybie PRZED punkty instalowane przez wizard raportujemy jako WARN, nie FAIL.
softfail() {
    if [[ "$BEFORE" -eq 1 ]]; then
        warn "$1 (instaluje Faza 2 wizarda)"
    else
        fail "$1"
    fi
}

# sudo bez pytania o hasło? Jeśli nie - pomijamy punkty, które go wymagają.
SUDO=""
if [[ $EUID -eq 0 ]]; then
    SUDO=""
    HAVE_ROOT=1
elif sudo -n true 2>/dev/null; then
    SUDO="sudo"
    HAVE_ROOT=1
else
    HAVE_ROOT=0
fi

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║        AUDYT SERWERA POD RAKAZO          ║"
echo "║       $(date +%Y-%m-%d\ %H:%M)                    ║"
echo "╚══════════════════════════════════════════╝"
if [[ "$BEFORE" -eq 1 ]]; then
    echo -e "${YELLOW}Tryb: audyt PRZED instalacją${NC} - Docker i kontenery jeszcze nie istnieją."
fi

# --- 1. System i zasoby ---
header "1. System i zasoby"

if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_NAME="${NAME:-nieznany} ${VERSION_ID:-}"
    if [[ "${ID:-}" == "ubuntu" && "${VERSION_ID:-}" == "24.04" ]]; then
        pass "System: $OS_NAME"
    elif [[ "${ID:-}" == "ubuntu" ]]; then
        warn "System: $OS_NAME (poradnik testowany na Ubuntu 24.04)"
    else
        warn "System: $OS_NAME (poradnik zakłada Ubuntu 24.04)"
    fi
else
    warn "Nie mogę odczytać /etc/os-release"
fi

CPUS=$(nproc 2>/dev/null || echo 0)
if [[ "$CPUS" -ge 2 ]]; then
    pass "CPU: $CPUS vCPU (minimum 2)"
else
    fail "CPU: $CPUS vCPU - za mało, minimum 2"
fi

RAM_MB=$(awk '/^MemTotal:/ {printf "%d", $2/1024}' /proc/meminfo 2>/dev/null || echo 0)
if [[ "$RAM_MB" -ge 3800 ]]; then
    pass "RAM: ${RAM_MB} MB (minimum 4 GB)"
elif [[ "$RAM_MB" -ge 1900 ]]; then
    fail "RAM: ${RAM_MB} MB - za mało na lokalne komputery botów (minimum 4 GB)"
else
    fail "RAM: ${RAM_MB} MB - za mało nawet na sam stack"
fi

DISK_FREE_GB=$(df -BG --output=avail / 2>/dev/null | tail -1 | tr -dc '0-9')
DISK_FREE_GB=${DISK_FREE_GB:-0}
if [[ "$DISK_FREE_GB" -gt 10 ]]; then
    pass "Dysk: ${DISK_FREE_GB} GB wolnego (minimum 10 GB)"
else
    fail "Dysk: ${DISK_FREE_GB} GB wolnego - obrazy Rakazo potrzebują ponad 10 GB"
fi

# --- 2. Docker ---
header "2. Docker"

if command -v docker >/dev/null 2>&1; then
    pass "Docker zainstalowany: $(docker --version 2>/dev/null | cut -d, -f1)"
else
    softfail "Docker nie zainstalowany"
fi

# Wersja pluginu nie ma znaczenia - dziś z repo Dockera przychodzi v5.x, wcześniej v2.x.
# Liczy się tylko to, że 'docker compose version' w ogóle działa.
if docker compose version >/dev/null 2>&1; then
    pass "Compose plugin: $(docker compose version --short 2>/dev/null)"
else
    softfail "Brak pluginu 'docker compose'"
fi

if id -nG "$(id -un)" 2>/dev/null | tr ' ' '\n' | grep -qx docker; then
    pass "Użytkownik $(id -un) w grupie docker"
elif [[ $EUID -eq 0 ]]; then
    warn "Audyt jako root - nie sprawdzam grupy docker zwykłego użytkownika"
else
    softfail "Użytkownik $(id -un) NIE jest w grupie docker (po dodaniu zaloguj się na nowo)"
fi

if docker ps >/dev/null 2>&1; then
    pass "Dostęp do demona Dockera bez sudo"
else
    softfail "Brak dostępu do demona Dockera bez sudo"
fi

# --- 3. Sieć i porty ---
header "3. Sieć i porty"

if command -v ufw >/dev/null 2>&1; then
    if [[ "$HAVE_ROOT" -eq 1 ]]; then
        UFW_STATUS=$($SUDO ufw status 2>/dev/null)
        if grep -q "Status: active" <<<"$UFW_STATUS"; then
            pass "UFW aktywny"
            if grep -qE '^80(/tcp)?[[:space:]]+ALLOW' <<<"$UFW_STATUS"; then
                pass "UFW przepuszcza port 80"
            else
                fail "UFW nie przepuszcza portu 80 (Let's Encrypt tego wymaga)"
            fi
            if grep -qE '^443(/tcp)?[[:space:]]+ALLOW' <<<"$UFW_STATUS"; then
                pass "UFW przepuszcza port 443"
            else
                fail "UFW nie przepuszcza portu 443"
            fi
        else
            fail "UFW zainstalowany, ale nieaktywny - najpierw zabezpiecz serwer (vps-security)"
        fi
    else
        warn "Brak sudo bez hasła - pomijam sprawdzenie reguł UFW"
    fi
else
    fail "Brak UFW - najpierw zabezpiecz serwer (vps-security)"
fi

# Nasłuchy: preferuj ss, fallback na netstat.
LISTEN=""
if command -v ss >/dev/null 2>&1; then
    LISTEN=$($SUDO ss -tlnH 2>/dev/null || ss -tlnH 2>/dev/null || true)
elif command -v netstat >/dev/null 2>&1; then
    LISTEN=$($SUDO netstat -tln 2>/dev/null || netstat -tln 2>/dev/null || true)
fi

listens_on() {
    # $1 = port; zwraca 0, gdy cokolwiek słucha na tym porcie
    grep -qE "[:.]$1[[:space:]]" <<<"$LISTEN"
}
listens_public() {
    # $1 = port; zwraca 0, gdy słucha na adresie innym niż loopback
    grep -E "[:.]$1[[:space:]]" <<<"$LISTEN" \
        | grep -qvE '(127\.0\.0\.1|\[::1\]):'"$1"'[[:space:]]'
}

if [[ -z "$LISTEN" ]]; then
    warn "Nie mogę odczytać listy nasłuchów (brak ss i netstat)"
else
    # 80 i 443 - Caddy potrzebuje ich wolnych; po instalacji zajmuje je sam.
    for p in 80 443; do
        if listens_on "$p"; then
            if systemctl is-active --quiet caddy 2>/dev/null; then
                pass "Port $p zajęty przez Caddy (poprawne po instalacji)"
            else
                warn "Port $p jest już zajęty - sprawdź czym: sudo ss -tlnp | grep ':$p'"
            fi
        else
            pass "Port $p wolny"
        fi
    done

    # 5173 - web; ma być tylko na loopbacku
    if listens_on 5173; then
        if listens_public 5173; then
            fail "Port 5173 (web) wystawiony poza loopback - to dziura, popraw bindowanie"
        else
            pass "Port 5173 (web) tylko na 127.0.0.1"
        fi
    else
        warn "Nikt nie słucha na 5173 - stack Rakazo jeszcze nie działa (audyt PRZED)"
    fi

    # 3100 - API; nie powinien być wystawiony na świat
    if listens_on 3100; then
        if listens_public 3100; then
            fail "Port 3100 (API) wystawiony na świat - Vite proxuje /api same-origin, nie wystawiaj go"
        else
            pass "Port 3100 (API) tylko na 127.0.0.1"
        fi
    else
        pass "Port 3100 (API) nie jest wystawiony"
    fi
fi

# --- 4. Kontenery Rakazo ---
header "4. Kontenery Rakazo"

if docker ps >/dev/null 2>&1; then
    PS_OUT=$(docker ps --format '{{.Names}}|{{.State}}|{{.Status}}' 2>/dev/null || true)
    ANY_RAKAZO=$(grep -c '^rakazo-' <<<"$PS_OUT" || true)
    if [[ "${ANY_RAKAZO:-0}" -eq 0 ]]; then
        warn "Brak działających kontenerów rakazo-* (audyt PRZED instalacją)"
    else
        for svc in postgres supervisor api worker web; do
            LINE=$(grep -E "^rakazo-${svc}-[0-9]+\|" <<<"$PS_OUT" | head -1)
            if [[ -z "$LINE" ]]; then
                fail "Kontener rakazo-${svc}-1 nie działa"
            else
                STATUS=$(cut -d'|' -f3 <<<"$LINE")
                if grep -q "unhealthy" <<<"$STATUS"; then
                    fail "rakazo-${svc}-1: $STATUS"
                elif grep -q "healthy" <<<"$STATUS"; then
                    pass "rakazo-${svc}-1: $STATUS"
                elif grep -q "^Up" <<<"$STATUS"; then
                    pass "rakazo-${svc}-1: $STATUS"
                else
                    warn "rakazo-${svc}-1: $STATUS"
                fi
            fi
        done

        BOTS=$(grep -cE '^rakazo-(bot|computer)' <<<"$PS_OUT" || true)
        if [[ "${BOTS:-0}" -gt 0 ]]; then
            pass "Aktywne komputery botów: ${BOTS}"
        else
            warn "Żaden komputer bota nie działa (normalne - startuje na żądanie, gaśnie po 10 min)"
        fi
    fi
else
    warn "Bez dostępu do Dockera nie sprawdzę kontenerów"
fi

# --- 5. Konfiguracja (.env) ---
header "5. Konfiguracja"

ENV_FILE="$RAKAZO_DIR/.env"
if [[ -f "$ENV_FILE" ]]; then
    pass "Znaleziono $ENV_FILE"

    PERMS=$(stat -c '%a' "$ENV_FILE" 2>/dev/null || echo "???")
    if [[ "$PERMS" == "600" ]]; then
        pass ".env ma uprawnienia 600"
    else
        fail ".env ma uprawnienia $PERMS - powinno być 600 (chmod 600 $ENV_FILE)"
    fi

    # Uwaga: czytamy TYLKO wartości jawne. Żadnych sekretów nie wypisujemy.
    get_env() { grep -E "^$1=" "$ENV_FILE" 2>/dev/null | tail -1 | cut -d= -f2-; }

    RHOST=$(get_env RAKAZO_HOST)
    if [[ -z "$RHOST" || "$RHOST" == "localhost" ]]; then
        fail "RAKAZO_HOST=${RHOST:-puste} - ustaw publiczną nazwę hosta, inaczej web odrzuci żądania"
    else
        pass "RAKAZO_HOST=$RHOST"
    fi

    ORIGIN_BAD=0
    for key in BETTER_AUTH_URL WEB_ORIGIN API_URL; do
        VAL=$(get_env "$key")
        if [[ "$VAL" != https://* ]]; then
            fail "$key=${VAL:-puste} - dla publicznego serwera musi być https://"
            ORIGIN_BAD=1
        fi
    done
    if [[ "$ORIGIN_BAD" -eq 0 ]]; then
        pass "Trzy originy (BETTER_AUTH_URL, WEB_ORIGIN, API_URL) na https://"
    fi

    SIGNUPS=$(get_env SIGNUPS_ENABLED)
    if [[ "$SIGNUPS" == "false" ]]; then
        pass "SIGNUPS_ENABLED=false (rejestracja zamknięta)"
    elif [[ "$SIGNUPS" == "true" ]]; then
        warn "SIGNUPS_ENABLED=true - zamknij rejestrację po założeniu konta ownera"
    else
        warn "SIGNUPS_ENABLED nieustawione"
    fi

    PROVIDER=$(get_env SANDBOX_PROVIDER)
    if [[ -n "$PROVIDER" ]]; then
        pass "SANDBOX_PROVIDER=$PROVIDER"
    else
        warn "SANDBOX_PROVIDER nieustawione (domyślnie docker)"
    fi

    # Obecność sekretów sprawdzamy po długości, nigdy po wartości.
    MISSING_SECRETS=""
    for key in POSTGRES_PASSWORD BETTER_AUTH_SECRET ENCRYPTION_KEY SCREEN_PROXY_SECRET SANDBOX_SUPERVISOR_TOKEN; do
        LEN=$(grep -E "^$key=" "$ENV_FILE" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d '[:space:]' | wc -c)
        if [[ "$LEN" -lt 9 ]]; then
            MISSING_SECRETS="$MISSING_SECRETS $key"
        fi
    done
    if [[ -z "$MISSING_SECRETS" ]]; then
        pass "Wszystkie wymagane sekrety w .env są wypełnione"
    else
        fail "Puste lub za krótkie sekrety w .env:$MISSING_SECRETS"
    fi
else
    warn "Brak $ENV_FILE (audyt PRZED instalacją; inna ścieżka? RAKAZO_DIR=... bash check.sh)"
fi

# --- 6. TLS ---
header "6. TLS"

if [[ -n "${RHOST:-}" && "${RHOST:-localhost}" != "localhost" ]]; then
    if command -v curl >/dev/null 2>&1; then
        HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "https://$RHOST" 2>/dev/null || echo "000")
        if [[ "$HTTP_CODE" == "200" ]]; then
            pass "https://$RHOST zwraca 200"
            # Samo 200 nie dowodzi, że API żyje - Vite oddaje index.html na każdą ścieżkę.
            AUTH_OK=$(curl -s --max-time 15 "https://$RHOST/api/auth/ok" 2>/dev/null || echo "")
            if grep -q '"ok"[[:space:]]*:[[:space:]]*true' <<<"$AUTH_OK"; then
                pass "Proxy /api działa (/api/auth/ok zwraca ok:true)"
            elif [[ -z "$AUTH_OK" ]]; then
                warn "/api/auth/ok nie odpowiedziało - sprawdź logi rakazo-api-1"
            else
                fail "/api/auth/ok nie zwraca ok:true - proxy /api albo API nie działa"
            fi
        elif [[ "$HTTP_CODE" == "000" ]]; then
            fail "https://$RHOST nie odpowiada (DNS, firewall albo brak certyfikatu)"
        else
            fail "https://$RHOST zwraca $HTTP_CODE"
        fi
    else
        warn "Brak curl - nie sprawdzę TLS"
    fi
else
    warn "Nie znam publicznej domeny - pomijam test TLS"
fi

if systemctl is-active --quiet caddy 2>/dev/null; then
    pass "Caddy działa"
elif command -v caddy >/dev/null 2>&1; then
    fail "Caddy zainstalowany, ale usługa nie działa"
else
    warn "Caddy nie zainstalowany (audyt PRZED albo inny reverse proxy)"
fi

# Obejście buga Rakazo #832 (upstream, od 2026-09-08): bez tej linii pulpit bota jest czarny.
if [[ -f /etc/caddy/Caddyfile ]]; then
    if grep -q 'path_regexp .*novnc/session' /etc/caddy/Caddyfile 2>/dev/null; then
        pass "Caddyfile: obejście czarnego pulpitu (uri path_regexp, Rakazo #832) obecne"
    elif [[ "$BEFORE" == "1" ]]; then
        warn "Caddyfile bez obejścia czarnego pulpitu - wizard doda je w Fazie 4c"
    else
        fail "Caddyfile bez obejścia czarnego pulpitu (Rakazo #832) - dopisz 'uri path_regexp' przed reverse_proxy (INSTRUKCJA, pkt 12)"
    fi
fi

# --- Podsumowanie ---
echo ""
echo "╔══════════════════════════════════════════╗"
echo "║              PODSUMOWANIE                ║"
echo "╠══════════════════════════════════════════╣"
echo -e "║  ${GREEN}PASS: $PASS${NC}  ${RED}FAIL: $FAIL${NC}  ${YELLOW}WARN: $WARN${NC}          ║"
echo "╚══════════════════════════════════════════╝"

if [[ "$BEFORE" -eq 1 && $FAIL -eq 0 ]]; then
    echo -e "\n${GREEN}Serwer nadaje sie pod Rakazo${NC} - brakuje tylko Dockera, robi to Faza 2.\n"
elif [[ $FAIL -eq 0 ]]; then
    echo -e "\n${GREEN}Wyglada dobrze!${NC}\n"
elif [[ $FAIL -le 2 ]]; then
    echo -e "\n${YELLOW}Kilka rzeczy do poprawienia - sprawdz punkty na czerwono.${NC}\n"
else
    echo -e "\n${RED}Serwer jeszcze nie jest gotowy - zacznij od punktow na czerwono.${NC}\n"
fi
