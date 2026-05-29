# noisy-chirp 🐦

Eine sehr penetrante Notification-App. Wiederkehrende Pflichten (z. B.
*Zahnbürstenkopf wechseln*) werden via [ntfy](https://ntfy.sh) aufs Handy
gepusht. Wer ignoriert, wird in immer enger werdenden Intervallen
nachgebombt — daher *chirp*. Wer zu reflexhaft wegtippt, kriegt einen
**Schwur-Prompt** vorgesetzt.

**Stack:** Elixir 1.19 · Phoenix 1.8 · LiveView 1.1 · OTP (ein GenServer
pro Task) · SQLite · ntfy · Docker Compose + Caddy.

---

## Architektur (Kurz)

* `Chirp.Reminders` — Ecto-Kontext für `Task` (eine Pflicht) und `Event`
  (Audit-Log für die Lügen-Heuristik).
* `Chirp.Engine.TaskServer` — **ein GenServer pro Task**. Hält den Timer
  via `Process.send_after/3`; bei `:fire` wird der Task aus der DB
  geladen, eskaliert und neu geplant. DB = Quelle der Wahrheit.
* `Chirp.Engine.{Supervisor,Registry,Boot}` — `DynamicSupervisor` +
  `Registry` (`:unique` per `task_id`) + Boot-Task, der beim App-Start
  alle aktiven Tasks hochfährt.
* `Chirp.Engine.Escalation` — reine Funktionen: `gap/1`, `priority/1`,
  `tags/1`, `text/3` für den „chirp"-Algorithmus.
* `Chirp.Notifier` / `Chirp.Ntfy` — Behaviour + ntfy.sh-Client. Tests
  swappen das Modul via `:noisy_chirp, :notifier`.

LiveView-Routen:

| Pfad             | Zweck                                              |
|------------------|----------------------------------------------------|
| `/`              | Read-only Dashboard aller Tasks                    |
| `/t/:token`      | Confirm-Seite (Ziel jedes ntfy-Taps)               |
| `/oath/:token`   | Schwur-Seite (`state = "awaiting_oath"`)           |

---

## Lokales Setup

```bash
mix setup          # deps + ecto.setup (create/migrate/seed) + assets
mix phx.server     # http://localhost:4000
```

Setze in `priv/repo/seeds.exs` ggf. ein eigenes `NTFY_TOPIC` (oder via
ENV beim Aufruf: `NTFY_TOPIC=… mix run priv/repo/seeds.exs`).

### Tests

```bash
mix test
```

Tests mocken ntfy automatisch über `Chirp.TestNotifier`.

---

## Eskalations-Algorithmus

```
gap(n)      = max(5min, 12h / 2^(n-1))
priority(n) = min(5, 2 + n)         # ntfy 1..5
tags(n)     = bell → bell+warning → rotating_light+warning → +skull/scream
```

→ konkret: 12 h, 6 h, 3 h, 1.5 h, 45 min, 22 min, 11 min, ~6 min, 5 min, 5 min …

## Lügenfaktor

Bei jedem `confirm_task`:

```
delta = 0
delta += 30 if latency <  8 s    # reflexhaft
delta += 10 if latency < 30 s
delta -= 15 if latency in 1..15 min
delta += 10 if reminder_count <= 1 and latency < 15 s
new_score = clamp(old + delta, 0..100)
```

Ab `lie_score >= 60` → `state = "awaiting_oath"`, sofortige
Schwur-Notification, normale Mahnungen pausieren. `swear_task` halbiert
den Score und gibt frei.

---

## Deploy via Docker Compose + Caddy

1. `cp .env.example .env` und Werte setzen
   (`SECRET_KEY_BASE` via `mix phx.gen.secret`).
2. `docker compose --env-file .env up -d --build`
3. DNS `A`-Record für `PHX_HOST` → Server-IP. Caddy holt automatisch ein
   Let's-Encrypt-Zertifikat beim ersten HTTPS-Aufruf.

Migrationen laufen beim Container-Start automatisch
(`Ecto.Migrator` im Application-Supervisor-Tree).
Mit `SEED_ON_BOOT=true` (Default in der Compose-Datei) wird zusätzlich
einmalig `priv/repo/seeds.exs` ausgeführt — idempotent.

Backup ist trivial — nur das SQLite-File im `app_data`-Volume:

```bash
docker compose cp app:/data/noisy_chirp.db ./backup-$(date +%F).db
```

---

## Tuning-Stellschrauben

* Ruhezeit pro Task: `base_interval_seconds` im DB-Eintrag.
* Eskalations-Tempo: `first_gap_ms` / `min_gap_ms` in
  `Chirp.Engine.Escalation`.
* Lügen-Empfindlichkeit: Schwellen in `Chirp.Reminders.lie_delta/2` und
  der Oath-Trigger (`@oath_threshold`).
* Neue Pflichten: weiterer `Task`-Eintrag — Engine-Supervisor startet
  automatisch einen GenServer beim `create_task/1`.

---

## Annahmen / Abweichungen vom ursprünglichen Prompt

* App-OTP-Name ist `:noisy_chirp` (Phoenix-Standard), Modul-Namespace
  ist `Chirp.*` (per `mix phx.new --module Chirp`).
* `Process.send_after/3` ist auf ~49 Tage begrenzt; für längere
  Wartezeiten plant der `TaskServer` Checkpoints alle 24 h und plant beim
  Wachwerden neu.
* Die Schwur-Notification wird in `ConfirmLive` versendet, sobald
  `confirm_task/1` `:awaiting_oath` zurückgibt — also vor dem
  `push_navigate` zur Oath-Seite. Damit ist die Push beim Sprung in den
  Schwur-Zustand garantiert genau einmal raus.
