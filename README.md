# MIVB reisinfo-databank

Een Oracle-databank op basis van de echte GTFS-dienstregeling van de MIVB (Brussel).
De databank beantwoordt de kernvraag van een reisinfo-app: *welke vertrekken zijn er
aan deze halte, op deze dag, vanaf dit uur?* Daarnaast kunnen reizigers favoriete
haltes bewaren en kunnen beheerders storingen melden, met een automatische auditlog.

Project voor het vak Data Management (EhB, 3de jaar).

## Inhoud

- **Import** van ±1,56 miljoen doortochten via SQL*Loader in staging-tabellen
- **Transformatie** naar een eigen genormaliseerd model met de juiste datatypes
- **Constraints** (PK, FK, UNIQUE, CHECK) en **sequences** voor surrogaatsleutels
- **Indexen** met een meting van hun effect (EXPLAIN PLAN en tijdsmeting)
- **Views** die de complexiteit van GTFS verbergen
- **Triggers**: automatische eindtijd en auditlog voor storingen
- **Security**: drie rollen en demogebruikers volgens least privilege

## Dataset

GTFS-feed van de MIVB via de [Mobility Database](https://mobilitydatabase.org)
(feed `mdb-1088`, versie van 17/03/2026, dienstregeling van 16/03/2026 tot 12/04/2026).
De tests gebruiken daarom woensdag 18 maart 2026 als testdag.

De GTFS-bestanden staan niet in de repository (`data/raw/` staat in `.gitignore`).
Download de feed, pak hem uit en zet deze bestanden in `data/raw/`:

`routes.txt`, `stops.txt`, `calendar.txt`, `calendar_dates.txt`, `trips.txt`,
`stop_times.txt`, `translations.txt`

## Vereisten

- Oracle Database XE met de pluggable database `XEPDB1` op `localhost:1521`
- VS Code met de Oracle SQL Developer-extensie, met twee connecties:
  - **Lokaal MIVB**: als `SYSTEM`
  - **MIVB project**: als `MIVB` (bestaat na stap 0)
- SQL*Loader (`sqlldr`) en SQL*Plus (`sqlplus`) als commando in PowerShell

## Mapstructuur

```
data/raw/   GTFS-bestanden (niet in git)
docs/       ERD, datamodel en ontwerpkeuzes
load/       SQL*Loader control files en laden.ps1; logs in load/logs/
sql/        de bouwscripts, in volgorde genummerd
tests/      controlescripts per bouwstap
```

## Installatie

Voer de scripts in deze volgorde uit. SQL-scripts open je in een worksheet en
voer je uit als script (**F5**) met de vermelde connectie.

| Stap | Script | Connectie | Wat |
|---|---|---|---|
| 0 | [sql/00_users_en_rollen.sql](sql/00_users_en_rollen.sql) | Lokaal MIVB (SYSTEM) | maakt de projectgebruiker `MIVB`; vervang eerst `<wachtwoord>` |
| 1 | [sql/01_staging_tabellen.sql](sql/01_staging_tabellen.sql) | MIVB project | staging-tabellen (alle kolommen VARCHAR2) |
| 2 | [sql/02_model_tabellen.sql](sql/02_model_tabellen.sql) | MIVB project | het eigen datamodel met constraints |
| 3 | [sql/03_sequences.sql](sql/03_sequences.sql) | MIVB project | sequences voor de surrogaatsleutels |
| 4 | [load/laden.ps1](load/laden.ps1) | PowerShell | laadt `data/raw` in de staging-tabellen |
| 5 | [sql/04_transformatie.sql](sql/04_transformatie.sql) | MIVB project | staging → model (duurt ongeveer een minuut) |
| 6 | [sql/05_indexen.sql](sql/05_indexen.sql) | MIVB project | indexen voor de use case |
| 7 | [sql/06_views.sql](sql/06_views.sql) | MIVB project | views |
| 8 | [sql/07_triggers.sql](sql/07_triggers.sql) | MIVB project | triggers op `storing` |
| 9 | [sql/08_rollen_en_gebruikers.sql](sql/08_rollen_en_gebruikers.sql) | Lokaal MIVB (SYSTEM) | rollen en demogebruikers |
| 10 | [sql/09_grants.sql](sql/09_grants.sql) | MIVB project | objectrechten per rol |

Het laadscript start je vanuit de projectmap; het vraagt het wachtwoord van MIVB:

```powershell
.\load\laden.ps1
```

Alle scripts zijn herhaalbaar. Let op twee afhankelijkheden:

- `04_transformatie.sql` maakt de tabellen eerst leeg, ook favorieten en storingen.
- `08_rollen_en_gebruikers.sql` verwijdert de rollen en maakt ze opnieuw aan;
  voer daarna altijd `09_grants.sql` opnieuw uit.

## Tests

Bij elke bouwstap hoort een controlescript in [tests/](tests/), uit te voeren als MIVB:

| Script | Na stap | Controleert |
|---|---|---|
| [01_controle_staging.sql](tests/01_controle_staging.sql) | 4 | aantallen en inhoud van de staging-tabellen |
| [02_controle_model.sql](tests/02_controle_model.sql) | 3 | tabellen en constraints via de data dictionary |
| [03_controle_transformatie.sql](tests/03_controle_transformatie.sql) | 5 | aantallen staging tegenover model, omzettingen |
| [04_performantie_indexen.sql](tests/04_performantie_indexen.sql) | 6 | uitvoeringsplan en tijd zonder en met index |
| [05_controle_views.sql](tests/05_controle_views.sql) | 7 | resultaten van de views |
| [06_controle_triggers.sql](tests/06_controle_triggers.sql) | 8 | eindtijd en auditlog (met ROLLBACK) |
| [07_controle_security.sql](tests/07_controle_security.sql) | 10 | rechten per demogebruiker |

De securitytest logt in als elke demogebruiker en toont per stap het verwachte
resultaat (OK, ORA-01031 of ORA-00942). Hij werkt met F5 in VS Code of in SQL*Plus:

```powershell
sqlplus /nolog "@tests/07_controle_security.sql"
```

## Demogebruikers

| Gebruiker | Rol | Mag |
|---|---|---|
| `mivb_app` | app_publiek | vertrekken en storingen lezen via views, gebruikers en favorieten beheren |
| `mivb_beheerder` | beheerder | storingen invoeren en oplossen, auditlog lezen |
| `mivb_analist` | analist | alles lezen behalve persoonsgegevens, niets wijzigen |

De demowachtwoorden staan bewust in [sql/08_rollen_en_gebruikers.sql](sql/08_rollen_en_gebruikers.sql),
zodat de tests zonder extra stappen werken. In een echte omgeving hoort dat niet.

## Documentatie

- [docs/Ontwerpkeuzes.md](docs/Ontwerpkeuzes.md): elke keuze met de reden erachter
- [docs/datamodel.md](docs/datamodel.md): het fysieke datamodel
- [docs/ERD.md](docs/ERD.md) en [docs/erd_conceptueel.drawio](docs/erd_conceptueel.drawio): het ERD
