# noisy-chirp — Build-Anweisung für Claude Code + Deploy-Runbook

Eine Notification-Bomber-App. Wiederkehrende Pflichten (z. B. „Zahnbürstenkopf wechseln") werden per **ntfy** aufs Handy gepusht. Tap → minimalistisches Frontend → Checkbox „Ja, ist gewechselt" → Ruhe für das Intervall. Ignoriert man, wird in **immer enger werdenden Intervallen** nachgebombt (daher *chirp*). Ein **Lügenfaktor** misst, wie der User reagiert, und kann eine Schwur-Notification erzwingen.

**Stack:** Elixir · Phoenix 1.8 · LiveView 1.1 (kein eigenes JS) · OTP (ein Prozess pro Task) · SQLite · ntfy · Deploy via Docker Compose + Caddy (Auto-HTTPS).

---

## Teil A — Prompt für Claude Code

> Alles ab hier bis „**Ende Teil A**" in Claude Code reinkopieren. Es ist als Anweisung an Claude Code formuliert.

---

Baue eine Fullstack-App namens **noisy-chirp** in **Elixir/Phoenix mit LiveView**. Arbeite die Punkte der Reihe nach ab, committe sinnvoll, und führe am Ende `mix test` aus. Frag nicht bei Kleinigkeiten nach — triff vernünftige Annahmen und dokumentiere sie in der `README.md`.

### 0. Projekt-Setup

```bash
# Falls nötig zuerst:  mix archive.install hex phx_new
mix phx.new noisy_chirp --database sqlite3 --no-mailer
cd noisy_chirp
mix ecto.create
```

Nutze die aktuelle stabile Phoenix-1.8-Generation (Bandit-Adapter, LiveView 1.1, Tailwind/daisyUI sind dabei). **Keine Authentifizierung** (`phx.gen.auth` NICHT nutzen) — die App ist persönlich, Zugriff läuft über unguessbare Tokens in den URLs.

Füge in `mix.exs` als Dependency `{:req, "~> 0.5"}` hinzu (HTTP-Client für ntfy). SQLite-Adapter (`ecto_sqlite3`) ist durch `--database sqlite3` bereits drin.

### 1. Datenmodell (Ecto-Schemas + Migrations)

**`Chirp.Reminders.Task`** — eine wiederkehrende Pflicht:

| Feld | Typ | Bedeutung |
|---|---|---|
| `id` | id | PK |
| `token` | string, unique | zufälliger URL-sicherer String (24 Byte, `:crypto.strong_rand_bytes`), für die Confirm-Links |
| `name` | string | z. B. `"Zahnbürstenkopf"` |
| `verb` | string | z. B. `"gewechselt"` (für Texte) |
| `base_interval_seconds` | integer | Ruhezeit nach Bestätigung, z. B. ~60 Tage = `5_184_000` |
| `ntfy_topic` | string | ntfy-Topic für diesen Task |
| `state` | string | `"calm"` \| `"nagging"` \| `"awaiting_oath"` |
| `reminder_count` | integer | wie oft seit Fälligkeit schon erinnert wurde (0 = ruhig) |
| `next_fire_at` | utc_datetime | wann die nächste Notification raus soll |
| `last_confirmed_at` | utc_datetime, nullable | letzte ehrliche Bestätigung |
| `lie_score` | integer, default 0 | 0–100, akkumulierter Lügenverdacht |
| `last_sent_at` | utc_datetime, nullable | wann zuletzt eine Notification rausging (für Reaktionszeit) |
| `active` | boolean, default true | |

**`Chirp.Reminders.Event`** — Audit-Log für die Lügen-Analyse:

| Feld | Typ | Bedeutung |
|---|---|---|
| `id` | id | PK |
| `task_id` | references(:tasks) | |
| `kind` | string | `"sent"` \| `"confirmed"` \| `"oath_sent"` \| `"sworn"` |
| `priority` | integer, nullable | ntfy-Priority bei `sent` |
| `reaction_latency_ms` | integer, nullable | bei `confirmed`/`sworn`: Zeit seit `last_sent_at` |
| `inserted_at` | utc_datetime | |

Schreibe einen Kontext `Chirp.Reminders` mit Funktionen: `list_tasks/0`, `get_task!/1`, `get_task_by_token/1`, `create_task/1`, `register_sent/2` (setzt `last_sent_at`, legt `sent`-Event an), `confirm_task/1`, `swear_task/1`, plus die Lügen-/Eskalations-Logik (siehe unten).

### 2. OTP — ein Prozess pro Task (das Herzstück)

Das ist der nischige, „extravagante" Kern. **Nicht** einen globalen Cron-Loop bauen, sondern echtes OTP:

- **`Chirp.Engine.TaskServer`** — ein `GenServer` pro aktivem Task. Hält den Task-State im Speicher, plant den nächsten „Schuss" via `Process.send_after(self(), :fire, ms)`. Beim `:fire`:
  1. Lade aktuellen Task aus der DB (Quelle der Wahrheit).
  2. Wenn `state == "calm"` und `next_fire_at` erreicht → Erstmahnung: `reminder_count = 1`, `state = "nagging"`.
  3. Wenn `state == "nagging"` → `reminder_count += 1`.
  4. Berechne **Priority + Tags + Text** aus `reminder_count` (Eskalation, s. u.), verschicke via `Chirp.Ntfy`, rufe `register_sent/2`.
  5. Plane das nächste `:fire` mit dem **schrumpfenden Gap** (s. u.).
- **`Chirp.Engine.Supervisor`** — `DynamicSupervisor`, der die `TaskServer` startet.
- **`Chirp.Engine.Registry`** — `Registry` (`:unique`), damit man pro `task_id` genau einen Prozess hat (`{:via, Registry, {Chirp.Engine.Registry, task_id}}`).
- **`Chirp.Engine`** — API-Modul: `start_all/0` (beim App-Boot alle aktiven Tasks starten), `start_task/1`, `wake/1` (Prozess sofort neu planen lassen, z. B. nach einer Bestätigung), `reschedule/1`.

Hänge `Registry`, `DynamicSupervisor` und einen kleinen Boot-Task (der `Chirp.Engine.start_all/0` aufruft) in den `Application`-Supervisor-Tree in `application.ex`. Lass die Server bei Crash sauber vom Supervisor neu starten (sie rekonstruieren ihren State aus der DB → idempotent).

### 3. Eskalations-Algorithmus („chirp")

Definiere in einem Modul `Chirp.Engine.Escalation` als reine Funktionen:

```
# Gap bis zur nächsten Mahnung, abhängig von reminder_count (n >= 1)
first_gap = 12 h
min_gap   = 5 min
gap(n) = max(min_gap, round(first_gap / 2^(n-1)))
# -> 12h, 6h, 3h, 1.5h, 45m, 22m, 11m, 5m, 5m, 5m, ...

priority(n) = min(5, 2 + n)          # ntfy 1..5, steigt schnell auf 5
tags(n)     = cond do
  n <= 1 -> ["bell"]
  n <= 3 -> ["bell","warning"]
  n <= 5 -> ["rotating_light","warning"]
  true   -> ["rotating_light","skull","scream"]
end
```

**Text-Eskalation** — eine Liste deutscher Templates, mit `reminder_count` immer dringlicher. Beispiele (verwende `task.name`/`task.verb`, baue mehr Varianten als hier gezeigt):

- n=1: `"Nah? Schon den #{name} #{verb}?"`
- n=2: `"Ähm. Der #{name}. Du weißt schon."`
- n=3: `"Ich frag jetzt zum dritten Mal. #{name}. #{verb}? 🙃"`
- n=4: `"DER #{name}. JETZT."`
- n=5: `"Ich höre nicht auf. Du weißt das, oder? #{name}. 🚨"`
- n>=6: `"chirp chirp chirp chirp #{name} chirp 💀"`

Im `state == "calm"` zählt nur: Wenn `now >= next_fire_at`, fällig werden. Solange noch nicht fällig, plant der `TaskServer` einfach das `:fire` auf `next_fire_at`.

### 4. Lügenfaktor

In `Chirp.Reminders` bei `confirm_task/1`:

1. `latency_ms = now - task.last_sent_at` (falls `last_sent_at` nil → behandle als „kein Verdacht").
2. Berechne Delta auf `lie_score`:
   ```
   delta = 0
   delta += 30 if latency_ms < 8_000          # zu schnell weggetippt = reflexhaft / gelogen
   delta += 10 if latency_ms < 30_000
   delta -= 15 if latency_ms in 60_000..900_000  # menschlich plausibel (1–15 min) -> Ehrlichkeits-Rabatt
   # Muster: immer schon bei der allerersten Mahnung instant bestätigt
   delta += 10 if task.reminder_count <= 1 and latency_ms < 15_000
   ```
   `new_score = clamp(task.lie_score + delta, 0, 100)`.
3. Lege ein `confirmed`-Event mit `reaction_latency_ms` an.
4. **Entscheidung:**
   - `new_score >= 60` → **NICHT** freigeben. Setze `state = "awaiting_oath"`, speichere `lie_score = new_score`, sende sofort die **Schwur-Notification** (Priority 5, Tags `["pray","skull"]`, Click → Oath-Seite), lege `oath_sent`-Event an. Plane KEINE normalen Mahnungen mehr, solange `awaiting_oath`.
   - sonst → **freigeben**: `state = "calm"`, `reminder_count = 0`, `lie_score = new_score`, `last_confirmed_at = now`, `next_fire_at = now + base_interval_seconds`. Dann `Chirp.Engine.wake(task)` damit der Server umplant.

`swear_task/1` (von der Oath-Seite): legt `sworn`-Event an, halbiert `lie_score`, gibt frei wie oben (`state = "calm"`, neues `next_fire_at`), weckt den Engine-Prozess.

Schwur-Text: `"Schwöre mir, dass du den #{name} wirklich #{verb} hast!!"`

### 5. ntfy-Client `Chirp.Ntfy`

Eine Funktion `publish(topic, opts)`. `opts`: `:title`, `:message`, `:priority` (1–5), `:tags` (Liste), `:click` (URL), optional `:actions`.

ntfy-Publish = HTTP `POST` auf `#{base_url}/#{topic}` mit dem Message-Body als Request-Body und Steuerung über Header:
- `Title`
- `Priority` (`"1"`–`"5"`)
- `Tags` (komma-separiert, z. B. `"rotating_light,skull"`)
- `Click` (URL, die beim Antippen geöffnet wird → unsere Confirm-Seite)
- optional `Actions` (z. B. eine `view`-Action „Erledigt" → Confirm-Seite)

Beispiel mit Req:

```elixir
def publish(topic, opts) do
  base = Application.fetch_env!(:noisy_chirp, :ntfy_base_url)
  headers =
    [{"Title", opts[:title]}, {"Priority", to_string(opts[:priority] || 3)}]
    |> maybe_put("Tags", Enum.join(opts[:tags] || [], ","))
    |> maybe_put("Click", opts[:click])

  Req.post!("#{base}/#{topic}", headers: headers, body: opts[:message] || "")
end
```

`base_url` und der `public_base_url` (für die `Click`-Links) kommen aus der Config (s. u.). Die Click-URL ist immer `"#{public_base_url}/t/#{task.token}"` bzw. für den Schwur `"#{public_base_url}/oath/#{task.token}"`.

### 6. Frontend (LiveView, SEHR minimalistisch, kein eigenes JS)

Routen in `router.ex`:
- `live "/", DashboardLive` — winzige Übersicht: pro Task Name, State, `lie_score`, „nächster Schuss". Reines Read-only-Dashboard, schlicht.
- `live "/t/:token", ConfirmLive` — **die Seite, die der ntfy-Tap öffnet.**
- `live "/oath/:token", OathLive` — die dramatische Schwur-Seite.

**`ConfirmLive`** (das Wichtigste, maximal reduziert):
- Lädt Task per Token (`mount`). Wenn Token unbekannt → freundliche 404-artige Meldung.
- Zeigt zentriert: die aktuelle Frage (z. B. „Schon den Zahnbürstenkopf gewechselt?"), **eine Checkbox** „Ja, ist gewechselt", und einen Button „Bestätigen". Enter im Formular = Submit.
- `phx-submit` → `confirm_task/1`. Wenn das Ergebnis `awaiting_oath` ist → `push_navigate` auf `/oath/:token`. Sonst → Erfolgs-State im selben LiveView: großes `"Erledigt. Ruhe für ~2 Monate. 🤫"`.
- Design: dunkler Hintergrund, eine Karte, große Schrift, viel Whitespace. Nutze die mitgelieferten daisyUI-Klassen, halte es auf ein einziges Element-Cluster reduziert. Keine Navigation, kein Footer.

**`OathLive`**:
- Roter/dramatischer Look. Großer Text `"Schwöre mir, dass du den X wirklich gewechselt hast!!"`, Checkbox „Ich schwöre 🤚", Button „Schwören". `phx-submit` → `swear_task/1` → Erfolgs-State.

Da LiveView server-seitig rendert, brauchst du für Checkbox+Submit **kein** Custom-JavaScript. WebSocket-Verbindung übernimmt Phoenix.

### 7. Config

In `config/runtime.exs` (zur Laufzeit, für Prod via ENV):

```elixir
config :noisy_chirp,
  ntfy_base_url: System.get_env("NTFY_BASE_URL", "https://ntfy.sh"),
  public_base_url: System.get_env("PUBLIC_BASE_URL", "http://localhost:4000")
```

Setze in der Prod-Endpoint-Config `check_origin` auf den `PHX_HOST` (Standard bei `phx.gen.release`). Stelle sicher, dass `PHX_HOST`, `SECRET_KEY_BASE`, `DATABASE_PATH`, `PORT` aus ENV gelesen werden (Default von Phoenix 1.8 passt schon).

### 8. Seeds

In `priv/repo/seeds.exs` lege den Zahnbürstenkopf-Task an, damit die App sofort läuft:

```elixir
Chirp.Reminders.create_task(%{
  name: "Zahnbürstenkopf",
  verb: "gewechselt",
  base_interval_seconds: 5_184_000,        # ~60 Tage
  ntfy_topic: System.get_env("NTFY_TOPIC", "noisy-chirp-DEINGEHEIMESTOPIC"),
  next_fire_at: DateTime.add(DateTime.utc_now(), 60, :second)  # erster Schuss in 1 min zum Testen
})
```

### 9. Tests

Schreibe `mix test`-Tests für:
- Eskalation: `gap/1`, `priority/1`, `tags/1` liefern die erwarteten Werte; Gap floored bei `min_gap`.
- Lügen-Logik: schnelle Bestätigung (<8 s) hebt `lie_score`; bei `>=60` resultiert `awaiting_oath`; `swear_task` halbiert Score und gibt frei.
- Confirm-Flow: `confirm_task` setzt `next_fire_at` korrekt und `reminder_count = 0`.
Mocke ntfy (z. B. via `Req.Test` oder ein konfigurierbares Notifier-Behaviour), damit Tests keine echten HTTP-Calls machen.

### 10. Release & Container

Generiere die Release-Artefakte:

```bash
mix phx.gen.release --docker
```

Passe das generierte `Dockerfile` so an, dass das SQLite-File unter einem mountbaren Pfad liegt (z. B. `DATABASE_PATH=/data/noisy_chirp.db`) und beim Start migriert + seeded wird. Lege zusätzlich an:

**`docker-compose.yml`** (App + Caddy):

```yaml
services:
  app:
    build: .
    environment:
      SECRET_KEY_BASE: ${SECRET_KEY_BASE}
      PHX_HOST: ${PHX_HOST}
      PUBLIC_BASE_URL: https://${PHX_HOST}
      NTFY_BASE_URL: ${NTFY_BASE_URL:-https://ntfy.sh}
      NTFY_TOPIC: ${NTFY_TOPIC}
      DATABASE_PATH: /data/noisy_chirp.db
      PORT: "4000"
    volumes:
      - app_data:/data
    restart: unless-stopped

  caddy:
    image: caddy:2-alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data
      - caddy_config:/config
    restart: unless-stopped

volumes:
  app_data:
  caddy_data:
  caddy_config:
```

**`Caddyfile`**:

```
{$PHX_HOST} {
    reverse_proxy app:4000
}
```

Caddy macht automatisch HTTPS via Let's Encrypt und reicht WebSockets (für LiveView) transparent durch.

Lege eine `.env.example` mit `SECRET_KEY_BASE`, `PHX_HOST`, `NTFY_TOPIC`, optional `NTFY_BASE_URL` an. Schreibe eine `README.md` mit Local-Dev (`mix phx.server`), Test- und Deploy-Hinweisen.

**Wichtig:** Stelle sicher, dass beim Container-Start (Entrypoint/Release-Hook) erst `Ecto.Migrator` läuft und optional die Seeds, **bevor** der Endpoint startet, damit `Chirp.Engine.start_all/0` schon Tasks findet.

*Ende Teil A.*

---

## Teil B — Deploy auf deinem Hetzner-Server

Annahme: Ubuntu/Debian, du hast SSH-Root-Zugang, der Code (aus Teil A) liegt in einem Git-Repo.

### B1. Docker installieren (einmalig)

```bash
ssh root@DEINE_SERVER_IP
curl -fsSL https://get.docker.com | sh
docker compose version    # prüfen, ob Compose-Plugin da ist
```

### B2. Firewall

```bash
ufw allow OpenSSH
ufw allow 80
ufw allow 443
ufw enable
```

### B3. Code holen & konfigurieren

```bash
mkdir -p /opt/noisy-chirp && cd /opt/noisy-chirp
git clone DEIN_REPO .

# Secret erzeugen:
docker run --rm hexpm/elixir:1.18.0-erlang-27.0-debian-bookworm-20240701-slim \
  /bin/sh -c "mix local.hex --force >/dev/null 2>&1; echo ok" 2>/dev/null
# Einfacher: einmal lokal `mix phx.gen.secret` laufen lassen und den Wert hier eintragen.

cat > .env <<'EOF'
SECRET_KEY_BASE=HIER_DEN_64-ZEICHEN-SECRET
PHX_HOST=chirp.deine-domain.de
NTFY_TOPIC=noisy-chirp-EIN-LANGER-ZUFALLSSTRING
NTFY_BASE_URL=https://ntfy.sh
EOF
```

> `NTFY_TOPIC` ist quasi dein Passwort — wähle einen langen, zufälligen String. Jeder, der das Topic kennt, kann mitlesen/pushen.

### B4. Starten

```bash
docker compose --env-file .env up -d --build
docker compose logs -f app      # Migrations + „Running ...Endpoint" sehen
```

Caddy holt sich beim ersten HTTPS-Zugriff automatisch ein Zertifikat (sobald die Domain zeigt — siehe Teil C).

### B5. Updates später

```bash
cd /opt/noisy-chirp && git pull
docker compose --env-file .env up -d --build
```

Backup ist trivial: das ist nur das SQLite-File im `app_data`-Volume:

```bash
docker compose cp app:/data/noisy_chirp.db ./backup-$(date +%F).db
```

---

## Teil C — Domain verbinden

1. **DNS setzen** beim Registrar/DNS-Provider deiner Domain:
   - `A`-Record: `chirp` (oder `@` für die Root-Domain) → **IPv4 deines Hetzner-Servers**.
   - Optional `AAAA`-Record → IPv6 des Servers.
   - TTL ruhig niedrig (300 s) während des Einrichtens.
2. **Warten**, bis es propagiert ist: `dig +short chirp.deine-domain.de` muss die Server-IP zeigen.
3. Da `PHX_HOST=chirp.deine-domain.de` in der `.env` steht und der `Caddyfile` `{$PHX_HOST}` nutzt, besorgt Caddy beim ersten Aufruf von `https://chirp.deine-domain.de` **automatisch** ein Let's-Encrypt-Zertifikat. Nichts weiter zu tun.
4. Test: `https://chirp.deine-domain.de/` → Dashboard erscheint, Schloss-Symbol im Browser.

> Hetzner-Hinweis: Falls du eine **Hetzner Cloud Firewall** (im Cloud-Panel, nicht `ufw`) nutzt, dort ebenfalls Ports **80** und **443** eingehend freigeben.

---

## Teil D — ntfy aufs Handy bringen

1. **ntfy-App** installieren (Android: Play Store / F-Droid; iOS: App Store).
2. In der App **„Subscribe to topic"** → exakt deinen `NTFY_TOPIC`-String eintragen, Server `ntfy.sh` (Default).
3. Fertig. Die erste Test-Notification kommt durch den Seed ~1 Minute nach dem ersten Start.

**Optional self-hosted ntfy** (noch nischiger, alles auf deinem Server): ntfy als weiteren Compose-Service laufen lassen, eine Subdomain `ntfy.deine-domain.de` in den `Caddyfile` aufnehmen und `NTFY_BASE_URL=https://ntfy.deine-domain.de` setzen. Für den Anfang reicht das öffentliche `ntfy.sh` aber völlig.

---

## Teil E — Den ganzen Loop testen

1. Nach dem Start kommt die erste Notification „Nah? Schon den Zahnbürstenkopf gewechselt?".
2. **Ignorieren** → die Mahnungen werden enger (12 h → 6 h → … → 5 min) und lauter (Priority/Tags steigen). Zum schnellen Testen `base_interval_seconds` und die Gaps im Seed/Escalation kurzzeitig auf Sekunden setzen.
3. **Tap** → `https://chirp.deine-domain.de/t/<token>` öffnet sich → Checkbox + Bestätigen.
4. **Zu schnell bestätigt (<8 s)** mehrfach → `lie_score` steigt → ab 60 kommt „Schwöre mir, dass du den Zahnbürstenkopf wirklich gewechselt hast!!" → Oath-Seite → Schwören → frei.
5. Ehrlich bestätigt → „Erledigt. Ruhe für ~2 Monate. 🤫", `next_fire_at` in ~60 Tagen.

---

### Tuning-Stellschrauben (alles in den Modulen aus Teil A)
- Ruhezeit pro Task: `base_interval_seconds`.
- Eskalations-Tempo: `first_gap`, `min_gap`, `2^(n-1)` in `Chirp.Engine.Escalation`.
- Lügen-Empfindlichkeit: die Schwellen (`8_000`, `30_000`, Plausibilitäts-Fenster) und der Oath-Trigger (`>= 60`).
- Neue Pflichten: einfach weitere `Task`-Einträge anlegen (eigenes Topic oder dasselbe) — der Engine-Supervisor startet automatisch einen Prozess dafür.
