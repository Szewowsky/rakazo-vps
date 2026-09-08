# Rakazo na własnym VPS - krok po kroku

Nie musisz być programistą. Potrzebujesz tylko:
- VPS z Ubuntu 24.04, **już zabezpieczony** (patrz niżej), minimum 2 vCPU i 4 GB RAM
- Subdomenę z rekordem A wskazującym na IP serwera
- Terminal na komputerze (Terminal na Macu, PowerShell na Windows)
- Około godziny (większość to czekanie na pobieranie obrazów)

## Krok zero: zabezpiecz serwer

Ten poradnik **nie zabezpiecza serwera**. Zakłada, że masz już: użytkownika nie-root, logowanie
kluczem SSH, aktywny UFW i fail2ban. Jeśli nie masz - zacznij tutaj:

**https://szewowsky.github.io/vps-security/**

Wróć, gdy tamten audyt świeci na zielono.

## Zanim zaczniesz

Podłącz się do serwera swoim użytkownikiem (nie rootem):

```
ssh twoj_user@TWOJE_IP
```

Jeśli masz inny port SSH (np. 2222):

```
ssh -p 2222 twoj_user@TWOJE_IP
```

## Sprawdź, czy serwer się nadaje (audyt)

Ze swojego komputera, z katalogu tego repo:

```
scp ./scripts/check.sh twoj_user@TWOJE_IP:/tmp/
ssh twoj_user@TWOJE_IP "bash /tmp/check.sh --before"
```

Zielone = OK, czerwone = do zrobienia. Flaga `--before` mówi skryptowi, że Dockera jeszcze nie ma -
dzięki niej cała sekcja Dockera wychodzi na żółto z dopiskiem "instaluje Faza 2", a nie na czerwono.
**Nie idź dalej**, jeśli czerwone jest RAM, dysk albo UFW.

---

## Krok 1: Docker

**Po co?** Rakazo to kilka usług naraz (baza, API, worker, strona, komputery botów).
Docker uruchamia je obok siebie, każdą w swoim pudełku.

Na serwerze:

```
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker $(id -un)
```

⚠️ `DEBIAN_FRONTEND=noninteractive` nie jest ozdobnikiem. Bez niego `apt-get` potrafi zawiesić się
na pytaniu w oknie konfiguracyjnym, którego w sesji SSH nie zobaczysz - i stoi tak w nieskończoność.

⚠️ **Teraz wyloguj się i zaloguj ponownie** (`exit`, potem znowu `ssh`). Bez tego Docker będzie
narzekał na brak uprawnień.

Test:

```
docker compose version
docker ps
```

Obie komendy muszą zadziałać **bez `sudo`**. Wersja Compose może być `v2.x` albo `v5.x` - obie są
poprawne, dziś z repo Dockera przychodzi v5.

⚠️ Bycie w grupie `docker` to praktycznie uprawnienia roota na tej maszynie. To cena za lokalne
komputery botów - warto o tym wiedzieć.

---

## Krok 2: Instalacja Rakazo

**Po co?** Ściągamy gotowe obrazy od autorów Rakazo. Nie budujemy niczego samodzielnie.

```
mkdir -p ~/rakazo && cd ~/rakazo
curl -fsSLO https://raw.githubusercontent.com/elie222/rakazo/main/infra/compose/install-images.sh
bash install-images.sh --prepare-only
```

Instalator pobrał pliki i stworzył `.env` z **losowo wygenerowanymi hasłami**. Nie wymyślasz ich sam.

⚠️ `.env` to Twój sejf. Nie wrzucaj go do internetu, nie wklejaj do czatu z AI, nie commituj.

---

## Krok 3: Ustaw swój adres w `.env`

**Po co?** Rakazo domyślnie myśli, że działa na Twoim laptopie. Musi wiedzieć, pod jakim adresem
będzie widoczny w internecie - inaczej zobaczysz biały ekran.

Otwórz plik:

```
nano ~/rakazo/.env
```

Zmień te linie (wpisz swoją domenę zamiast `rakazo.twojadomena.pl`):

```
BETTER_AUTH_URL=https://rakazo.twojadomena.pl
WEB_ORIGIN=https://rakazo.twojadomena.pl
API_URL=https://rakazo.twojadomena.pl
RAKAZO_HOST=rakazo.twojadomena.pl
SANDBOX_PROVIDER=docker
SIGNUPS_ENABLED=true
SIGNUP_ALLOWLIST=
```

Zwróć uwagę: trzy pierwsze linie mają `https://`, a `RAKAZO_HOST` **nie ma** - to sama nazwa.

⚠️ **`SIGNUP_ALLOWLIST` zostaw PUSTE.** Wygląda to niebezpiecznie, ale jest odwrotnie. Kiedy wpiszesz
tam swój adres, Rakazo włącza wymóg potwierdzenia e-maila przy rejestracji - a ta instalacja nie ma
skonfigurowanej poczty wychodzącej, więc mail nigdy nie dotrze i **nie zalogujesz się na własne konto**.
Zamiast tego: rejestracja jest otwarta przez kilka minut (Krok 6), zakładasz konto i od razu ją zamykasz.
Nie zostawiaj jej otwartej dłużej, niż potrzeba.

Na koniec dopisz na dole pliku:

```
SANDBOX_IDLE_MS=600000
RAKAZO_COMPUTER_MEMORY=4g
```

Pierwsza linia: komputer bota gaśnie po 10 minutach bezczynności. Oszczędza pamięć.

Druga linia to sufit pamięci na jeden komputer bota. Domyślne `2g` bywa za mało dla Chromium
i kontener potrafi zginąć w środku zadania. **Na serwerze 8 GB wpisz `4g`. Na 4 GB pomiń tę linię**
(zostaw domyślne `2g`) - inaczej zabraknie pamięci na resztę. Format to `4g` albo `1536m`;
`4GB` nie zadziała i zablokuje start.

Zapisz (Ctrl+O, Enter) i wyjdź (Ctrl+X). Potem:

```
chmod 600 ~/rakazo/.env
```

---

## Krok 4: Uruchom Rakazo

```
cd ~/rakazo
bash install-images.sh
```

To pobiera **6,8 GB** obrazów. Na szybkim łączu hostingu schodzi w 2-3 minuty, na wolniejszym
potrafi zająć kwadrans. Zrób sobie kawę.

Na końcu zobaczysz: `Rakazo is starting at http://127.0.0.1:5173`.

Sprawdź:

```
docker compose --env-file .env -f docker-compose.images.yml ps -a
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:5173
```

Powinno być `200`. Pięć usług (`postgres`, `supervisor`, `api`, `worker`, `web`) w stanie `running`.
Dwie inne (`computer`, `data-init`) będą `exited` - **tak ma być**, to jednorazowe zadania.

⚠️ Zwróć uwagę na `-a` na końcu pierwszej komendy. Bez niego zobaczysz tylko pięć działających usług,
bo `docker compose ps` domyślnie ukrywa te zakończone. Pięć linii zamiast siedmiu to nie jest błąd.

---

## Krok 5: HTTPS (żeby wejść z przeglądarki)

**Po co?** Na razie Rakazo słucha tylko "od środka" serwera. Caddy to mały serwer, który wystawia go
do internetu i **sam załatwia darmowy certyfikat** od Let's Encrypt.

Najpierw otwórz porty:

```
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw status
```

⚠️ Sprawdź, czy na liście **nadal jest Twój port SSH**. Jeśli go nie ma - nie ruszaj dalej.

Zainstaluj Caddy:

```
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y caddy
```

Skonfiguruj:

```
sudo nano /etc/caddy/Caddyfile
```

Wyczyść zawartość i wpisz (swoją domenę i swój e-mail):

```
{
	email twoj@email.pl
}

rakazo.twojadomena.pl {
	reverse_proxy 127.0.0.1:5173
}
```

Zapisz i przeładuj:

```
sudo caddy validate --config /etc/caddy/Caddyfile
sudo systemctl reload caddy
```

Poczekaj kilkanaście sekund i wejdź w przeglądarce na `https://rakazo.twojadomena.pl`.
Powinna być kłódka i strona logowania.

### Sprawdź, czy backend naprawdę odpowiada

Sama strona zwróci `200` nawet wtedy, gdy API leży - panel oddaje tę samą stronę na każdy adres.
Zrób więc dwa dodatkowe testy (z dowolnego komputera):

```
curl -s https://rakazo.twojadomena.pl/api/auth/ok
curl -s https://rakazo.twojadomena.pl/api/auth/get-session
```

Pierwsza ma zwrócić `{"ok":true}`, druga `null`. Jeśli zamiast tego widzisz kod HTML - API nie
odpowiada i nie ma sensu iść dalej: `docker logs rakazo-api-1 --tail 80`.

---

## Krok 6: Załóż konto (i zamknij drzwi)

**Po co?** Pierwsza osoba, która się zarejestruje, zostaje właścicielem całej instalacji.
Ma to być Twoje konto, nie przypadkowego bota z internetu.

⚠️ Rejestracja jest w tej chwili **otwarta dla każdego**, bo allowlista jest pusta (patrz Krok 3).
To okno na kilka minut, nie stan docelowy. Zrób ten krok od razu po Kroku 5, nie odkładaj na wieczór.

1. Wejdź na `https://rakazo.twojadomena.pl` i **od razu** załóż konto na swój e-mail.
   Żadnego maila potwierdzającego nie dostaniesz i nie jest potrzebny - po rejestracji jesteś zalogowany.
2. Zaloguj się.
3. Dopiero teraz zamknij rejestrację. Na serwerze:

```
cd ~/rakazo
nano .env      # zmień SIGNUPS_ENABLED=true na SIGNUPS_ENABLED=false
docker compose --env-file .env -f docker-compose.images.yml up -d api worker web
```

Test: otwórz stronę w oknie incognito i spróbuj założyć konto na inny adres. Powinieneś dostać
komunikat, że rejestracja jest zamknięta.

⚠️ Jeśli nadal się da - wyłącz rejestrację również w ustawieniach w UI. Zmienna w `.env` działa
tylko jako wartość startowa; po pierwszym uruchomieniu rządzą ustawienia właściciela.

---

## Krok 7: Podepnij model

**Po co?** Rakazo samo nie myśli - to szkielet dla bota. Mózg podpinasz swój.

Najprościej: załóż konto na **openrouter.ai**, wygeneruj klucz API i wklej go w Rakazo w
Settings → Models. Jeden klucz daje dostęp do wielu modeli.

Test: stwórz pierwszego bota, napisz do niego "cześć" i poczekaj na odpowiedź.

⚠️ Klucze do **innych** usług (te, z których mają korzystać boty) nie idą do `.env`. Rakazo ma na nie
sejf sekretów w panelu - nazwane sekrety w przestrzeni roboczej i poświadczenia per bot. Tam je wpisuj.
Backup z Kroku 10 ich nie obejmuje, więc zapisz je sobie osobno.

---

## Krok 8: Sprawdź komputer bota

**Po co?** To jest ta część, dla której się w to bawimy - bot ma swój pulpit z przeglądarką.

1. Otwórz bota i kliknij **"Open computer"**.
2. Napisz mu: *"Otwórz w przeglądarce stronę example.com i powiedz mi, co na niej jest."*
3. Patrz na ekran - powinieneś zobaczyć startującą przeglądarkę.

⚠️ Komputer bota startuje **dopiero wtedy, gdy jest potrzebny**, i gaśnie po 10 minutach
bezczynności. Pusty ekran po dłuższej przerwie to nie awaria.

⚠️ Każdy aktywny komputer bota zjada 1-2 GB RAM. Przy 4 GB serwera - jeden bot naraz.

---

## Krok 9: Pierwsza rutyna

**Po co?** Rutyna to zadanie, które bot robi sam, o wyznaczonej porze. Tu zaczyna się zabawa.

Przykład: bot "Poranny radar", instrukcja *"codziennie o 8:15 otwórz news.ycombinator.com,
wybierz 3 najciekawsze wpisy i wypisz je z linkami"*.

Nie czekaj do rana - kliknij **"Run now"** i zobacz wynik od razu.

⚠️ Harmonogram liczy się według strefy czasowej serwera. Sprawdź ją: `timedatectl`.

---

## Krok 10: Backup i aktualizacje

### Backup

Dane siedzą w wolumenach Dockera, nie w plikach, które widzisz. Backup robi się tak:

```
mkdir -p ~/backups/rakazo-$(date +%F) && cd ~/backups/rakazo-$(date +%F)
docker exec rakazo-postgres-1 pg_dumpall -U rakazo > rakazo_pg.sql
docker run --rm -v rakazo_appdata:/data -v $PWD:/out alpine:3.20 tar czf /out/rakazo_appdata.tar.gz -C /data .
cp ~/rakazo/.env env.bak && chmod 600 env.bak
sha256sum ./* > SHA256SUMS
ls -la
```

⚠️ `env.bak` zawiera wszystkie hasła. Trzymaj go u siebie, nie w chmurze bez szyfrowania.

Jeśli Twój hosting ma snapshoty maszyny - zrób też snapshot przed każdą większą zmianą.

### Aktualizacja

```
cd ~/rakazo
docker compose --env-file .env -f docker-compose.images.yml pull
docker compose --env-file .env -f docker-compose.images.yml up -d --wait --wait-timeout 300
```

⚠️ **Zrób backup przed aktualizacją.** Domyślny tag `edge` to najświeższe buildy - bywa, że coś
w nich nie działa.

⚠️ Samo `up -d` nie wystarczy - bez `pull` nic się nie zaktualizuje.

---

## Gotowe!

Uruchom audyt ponownie:

```
bash /tmp/check.sh
```

Teraz powinno być dużo więcej zielonego. Masz własny zespół botów na własnym serwerze.

---

## Coś poszło nie tak?

Lista rzeczy, na które sam się nadziałem. Każda z objawem, przyczyną i komendą.

### 1. Założyłem konto i nie mogę się zalogować - czeka na potwierdzenie e-maila

**Objaw:** rejestracja przechodzi, ale zamiast panelu widzisz prośbę o kliknięcie w link wysłany
na e-mail. Mail nigdy nie przychodzi (sprawdziłeś też spam).

**Przyczyna:** w `.env` jest niepusta `SIGNUP_ALLOWLIST`. Niepusta allowlista włącza wymóg
weryfikacji adresu, a ta instalacja nie ma skonfigurowanej poczty wychodzącej (SMTP) - nie ma czym
tego maila wysłać.

```
cd ~/rakazo
sed -i "s|^SIGNUP_ALLOWLIST=.*|SIGNUP_ALLOWLIST=|" .env
docker compose --env-file .env -f docker-compose.images.yml up -d api worker web
```

Potem zarejestruj się jeszcze raz i **od razu** zamknij rejestrację (Krok 6).

### 2. Klucz Composio jest odrzucany, choć wygląda poprawnie

**Objaw:** wklejasz klucz do integracji Composio, a połączenie jest odrzucane.

**Przyczyna:** Composio ma dwa rodzaje kluczy, wyglądają niemal identycznie. Rakazo potrzebuje
klucza z trybu **PLATFORM**, zaczynającego się od `ak_`. Klucz `ck_` pochodzi z innego trybu
i nie zadziała, ile razy byś go nie wkleił.

**Co robisz:** w panelu Composio przełącz się na tryb PLATFORM i wygeneruj klucz stamtąd.
Weryfikacja to spojrzenie na dwa pierwsze znaki.

### 3. Bot przy każdym ruchu prosi o zgodę, rutyny nie robią nic

**Objaw:** bot staje przy pierwszej poważniejszej czynności i czeka na potwierdzenie. Rutyna
o 7 rano nie robi nic, bo o tej porze nikt nie klika.

**Przyczyna:** automatyczny recenzent czynności ma domyślnie **1,5 sekundy** na ocenę. Żaden model
się w tym nie mieści, więc recenzent milczy i decyzja spada na człowieka.

```
cd ~/rakazo
cat >> .env <<'EOF'
RAKAZO_AUTO_REVIEW_PROVIDER=openrouter
RAKAZO_AUTO_REVIEW_MODEL=google/gemini-3.1-flash-lite
RAKAZO_AUTO_REVIEW_TIMEOUT_MS=30000
EOF
docker compose --env-file .env -f docker-compose.images.yml up -d api worker
```

### 4. Przeglądarka bota nie wstaje po nagłym padzie

**Objaw:** kontener komputera się wywalił albo serwer został zrestartowany w trakcie pracy bota.
Pulpit jest, ale Chromium nie startuje.

**Przyczyna:** Chromium zostawia w profilu plik-blokadę, żeby dwie kopie nie pisały po tych samych
danych. Przy czystym zamknięciu sam go sprząta, przy nagłym padzie plik zostaje.

Wewnątrz komputera bota (przez terminal na jego pulpicie):

```
rm -f "$HOME/.browser-profiles/chromium/SingletonLock" \
      "$HOME/.browser-profiles/chromium/SingletonCookie" \
      "$HOME/.browser-profiles/chromium/SingletonSocket"
```

Nic nie tracisz - to pliki tymczasowe, nie Twoje zalogowane sesje.

### 5. "Ekran zajęty przez nowszą sesję"

**Objaw:** otwierasz pulpit bota i dostajesz komunikat, że ekran przejęła nowsza sesja.
Klikanie w kółko nic nie daje.

**Przyczyna:** pulpit ma jednego posiadacza naraz. Otworzyłeś go w przeglądarce, potem w aplikacji
desktopowej, a wcześniejsza karta nie zamknęła się porządnie - instalacja wciąż uważa tamtą sesję
za żywą.

**Co robisz:** w panelu przy komputerze bota użyj **Recover computer**. To odbiera zawieszoną
dzierżawę ekranu i przywraca ostatni zapisany stan pulpitu. Niezapisana robota z tamtej sesji
może przepaść, więc nie klikaj tego w środku ważnego zadania.

### 6. Brakuje mi dwóch kontenerów na liście

**Objaw:** `docker compose ps` pokazuje pięć usług, a instrukcja mówi o siedmiu.

**Przyczyna:** `computer` i `data-init` to zadania jednorazowe. Kończą się poprawnie i przechodzą
w stan `exited`, a `docker compose ps` domyślnie pokazuje tylko działające.

```
cd ~/rakazo
docker compose --env-file .env -f docker-compose.images.yml ps -a
```

### 7. Instalacja stoi i nic się nie dzieje

**Objaw:** `bash install-images.sh` wisi kilka minut bez widocznego postępu.

**Przyczyna:** pobiera 6,8 GB obrazów. Na szybkim łączu hostingu schodzi to w 2-3 minuty,
na wolniejszym w kwadrans. To nie jest zawieszenie.

Podgląd z drugiego terminala:

```
docker images | grep rakazo
df -h /
```

Jeśli po kwadransie nadal nic - przerwij i powtórz `bash install-images.sh`. Instalator zachowa
istniejący `.env` i dociągnie tylko brakujące warstwy.

### 8. `apt-get install` wisi w nieskończoność

**Objaw:** instalacja pakietu stoi, w logu widać `unable to initialize frontend: Dialog`
albo `dpkg-preconfigure: unable to re-open stdin`.

**Przyczyna:** pakiet chce zadać pytanie w oknie konfiguracyjnym, którego w sesji SSH nie ma.
Proces czeka na odpowiedź, której nigdy nie dostanie, i blokuje blokadę `dpkg`.

```
sudo pkill -f apt-get
sudo dpkg --configure -a --force-confdef --force-confold
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y NAZWA_PAKIETU
```

Prefiks `DEBIAN_FRONTEND=noninteractive` dawaj przy **każdej** instalacji pakietów, nie tylko
przy naprawie.

### 9. Panel pokazuje "update available" przy komputerze bota

**Objaw:** przy komputerze bota wisi informacja o dostępnej aktualizacji, klikasz i nic się nie zmienia -
komunikat wraca.

**Przyczyna:** w wersjach do początku września to pole było ustawione praktycznie zawsze,
niezależnie od stanu obrazu. To nie był sygnał, tylko szum. W nowszych wersjach zastąpiło je pole
opisujące, czy aktualizacja jest w ogóle możliwa (`canUpdate`), i wtedy komunikat już coś znaczy.

**Co robisz:** na starszym obrazie zignoruj. Na nowszym: odświeżenie komputera bota **rekreuje
kontener** (katalog domowy jest zapisywany i przywracany, ale to nie jest darmowa operacja) -
nie odpalaj tego w oknie, w którym mają lecieć rutyny.

### 10. Rutyna wisi i nigdy się nie kończy

**Objaw:** zadanie zostało w stanie "w trakcie", w wątku nic nie przybywa.

**Przyczyna:** worker został zrestartowany w trakcie wykonywania zadania. Run zostaje wtedy
osierocony - nikt go już nie dokończy.

```
docker logs rakazo-worker-1 --tail 60
```

**Co robisz:** uruchom rutynę ponownie ("Run now"). Na przyszłość: restartuj worker wtedy, gdy nic
nie leci, a nie w środku okna rutyn.

### 11. Bot ginie w środku zadania, bez błędu

**Objaw:** komputer bota nagle znika, zadanie urywa się w połowie, w logach nie ma sensownego wyjaśnienia.

**Przyczyna:** komputer bota ma twardy sufit pamięci (domyślnie 2 GB, razem z obszarem wymiany).
Xvfb, menedżer okien i Chromium z kilkoma kartami potrafią go przekroczyć - wtedy system ubija
kontener bez ceregieli.

```
free -h
docker stats --no-stream
```

Na serwerze 8 GB podnieś limit, na 4 GB raczej odciąż bota (mniej kart, jedno zadanie naraz):

```
cd ~/rakazo
sed -i "s|^RAKAZO_COMPUTER_MEMORY=.*|RAKAZO_COMPUTER_MEMORY=4g|" .env
grep -q '^RAKAZO_COMPUTER_MEMORY=' .env || echo 'RAKAZO_COMPUTER_MEMORY=4g' >> .env
docker compose --env-file .env -f docker-compose.images.yml up -d supervisor
```

Format musi być `4g` albo `1536m`. Wpisanie `4GB` wywali usługę przy starcie.

---

Materiał towarzyszący do filmu: [Robert Szewczyk](https://youtube.com/@robert_szewczyk)

Rakazo to projekt [elie222/rakazo](https://github.com/elie222/rakazo) na licencji Apache 2.0.
Ten poradnik jest nieoficjalny.
