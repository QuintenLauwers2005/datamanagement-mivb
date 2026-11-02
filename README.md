# MIVB reisinfo-databank

Een Oracle-databank op basis van de echte GTFS-dienstregeling van de MIVB (Brussel).
De databank beantwoordt de kernvraag van een reisinfo-app: *welke vertrekken zijn er
aan deze halte, op deze dag, vanaf dit uur?* Daarnaast kunnen reizigers favoriete
haltes bewaren en kunnen beheerders storingen melden, met een automatische auditlog.

Project voor het vak Data Management (EhB, 3de jaar).

## Toegepaste concepten

De kolom *Leerstof* duidt de concepten uit de les aan. De andere rijen zijn de
stappen die nodig zijn om de data in het model te krijgen.

| Concept | Leerstof | Script | Test |
|---|---|---|---|
| DDL: datamodel met constraints (PK, FK, UNIQUE, CHECK) | ✔ | [02_model_tabellen.sql](sql/02_model_tabellen.sql) | [02_controle_model.sql](tests/02_controle_model.sql) |
| Data dictionary (`USER_TABLES`, `USER_SEQUENCES`, `USER_INDEXES`, `USER_CONSTRAINTS`, ...) | ✔ | opruimblokken bovenaan [01](sql/01_staging_tabellen.sql), [02](sql/02_model_tabellen.sql), [03](sql/03_sequences.sql) en [05](sql/05_indexen.sql): kijken wat er al bestaat | [02_controle_model.sql](tests/02_controle_model.sql) |
| Sequences voor surrogaatsleutels | ✔ | [03_sequences.sql](sql/03_sequences.sql) | [02_controle_model.sql](tests/02_controle_model.sql) |
| Indexen, met meting van het effect | ✔ | [05_indexen.sql](sql/05_indexen.sql) | [04_performantie_indexen.sql](tests/04_performantie_indexen.sql) |
| Views | ✔ | [06_views.sql](sql/06_views.sql) | [05_controle_views.sql](tests/05_controle_views.sql) |
| Triggers (eindtijd en auditlog) | ✔ | [07_triggers.sql](sql/07_triggers.sql) | [06_controle_triggers.sql](tests/06_controle_triggers.sql) |
| Security: rollen, gebruikers, least privilege | ✔ | [08_rollen_en_gebruikers.sql](sql/08_rollen_en_gebruikers.sql), [09_grants.sql](sql/09_grants.sql) | [07_controle_security.sql](tests/07_controle_security.sql) |
| Import via staging (SQL*Loader) | | [01_staging_tabellen.sql](sql/01_staging_tabellen.sql), [laden.ps1](load/laden.ps1) | [01_controle_staging.sql](tests/01_controle_staging.sql) |
| Transformatie naar de juiste datatypes | | [04_transformatie.sql](sql/04_transformatie.sql) | [03_controle_transformatie.sql](tests/03_controle_transformatie.sql) |

## Dataset

GTFS-feed van de MIVB (`mdb-1088`) via de Mobility Database, de versie van
17/03/2026, met een dienstregeling van 16/03/2026 tot 12/04/2026:

https://files.mobilitydatabase.org/mdb-1088/mdb-1088-202603170054/mdb-1088-202603170054.zip

Gebruik precies deze versie. Op de Mobility Database staat standaard de nieuwste
feed, en daarmee kloppen de aantallen in de tests niet meer (1.559.649 doortochten,
2.752 haltes). De tests gebruiken woensdag 18 maart 2026 als testdag, en die datum
valt niet in elke versie van de feed.

De GTFS-bestanden staan niet in de repository (`data/raw/` staat in `.gitignore`).
Pak de zip uit in `data/raw/`. Gebruikt worden: `routes.txt`, `stops.txt`,
`calendar.txt`, `calendar_dates.txt`, `trips.txt`, `stop_times.txt` en `translations.txt`.

Licentie: CC BY 4.0. *Source: STIB-MIVB – Open Data – 16 maart 2026. Contains data
originally published by STIB-MIVB, modified by Quinten Lauwers.* Zie [docs/bronnen.md](docs/bronnen.md).

## Vereisten

**Oracle XE in Docker.** De image `gvenzl/oracle-xe:latest` (Oracle XE 21.3.0) met de
pluggable database `XEPDB1` op poort 1521:

```powershell
docker run -d --name oracle -p 1521:1521 -e ORACLE_PASSWORD=<wachtwoord_system> gvenzl/oracle-xe:latest
docker logs -f oracle
```

Dit project is gebouwd met de image met digest
`sha256:c2682a4216b0fe65537912c4a049c7e5c15a85bb7c94bb8137d5f2d2eef60603`. `latest` kan
later naar een andere versie wijzen; `gvenzl/oracle-xe@sha256:...` haalt precies deze image op.

De eerste start duurt enkele minuten. De databank is klaar wanneer in de logs
`DATABASE IS READY TO USE!` verschijnt. Daarna start je de container met `docker start oracle`.

**Oracle Instant Client** (voor de commando's in PowerShell). Download van oracle.com
deze drie pakketten, **alle drie in exact dezelfde versie** (hier 23.26), en pak ze
uit in dezelfde map:

- *Basic*: de basis
- *SQL\*Plus*: voor `sqlplus`
- *Tools*: voor `sqlldr` (SQL*Loader zit **niet** in het Basic-pakket)

Zet die map in de `PATH`. Controle: `sqlldr` en `sqlplus -v` werken in een nieuwe PowerShell.

**VS Code** met de extensie Oracle SQL Developer en twee connecties naar
`localhost:1521/XEPDB1`:

- **Lokaal MIVB**: als `SYSTEM`
- **MIVB project**: als `MIVB` (die gebruiker bestaat na het eerste script)

## Mapstructuur

```
data/raw/   GTFS-bestanden (niet in git)
docs/       datamodel, ERD en ontwerpkeuzes
load/       SQL*Loader control files en laden.ps1; logs in load/logs/
sql/        de bouwscripts, in volgorde genummerd
tests/      controlescripts per bouwstap
```

## Installatie

SQL-scripts open je in een worksheet en voer je uit als script (**F5**) met de
vermelde connectie. Voer ze uit in deze volgorde:

| Script | Connectie | Wat | Waarom op deze plaats |
|---|---|---|---|
| [00_users_en_rollen.sql](sql/00_users_en_rollen.sql) | Lokaal MIVB (SYSTEM) | maakt de projectgebruiker `MIVB`; vervang eerst `<wachtwoord>` | alle objecten komen in het schema MIVB |
| [01_staging_tabellen.sql](sql/01_staging_tabellen.sql) | MIVB project | staging-tabellen (alle kolommen VARCHAR2) | SQL*Loader laadt hierin |
| [02_model_tabellen.sql](sql/02_model_tabellen.sql) | MIVB project | het eigen datamodel met constraints | de tabellen moeten bestaan voor de sequences (03) en de transformatie (04) |
| [03_sequences.sql](sql/03_sequences.sql) | MIVB project | sequences voor de surrogaatsleutels | koppelt zich als DEFAULT aan tabellen uit 02 |
| [laden.ps1](load/laden.ps1) | PowerShell | laadt `data/raw` in de staging-tabellen | heeft de staging-tabellen uit 01 nodig |
| [04_transformatie.sql](sql/04_transformatie.sql) | MIVB project | staging → model (duurt ongeveer een minuut) | heeft geladen staging-data nodig |
| [05_indexen.sql](sql/05_indexen.sql) | MIVB project | indexen voor de use case | na het laden: inladen gaat sneller zonder indexen |
| [06_views.sql](sql/06_views.sql) | MIVB project | views | lezen uit de tabellen uit 02; 09 geeft rechten op deze views |
| [07_triggers.sql](sql/07_triggers.sql) | MIVB project | triggers op `storing` | heeft de tabellen `storing` en `storing_log` (02) en `seq_storing_log` (03) nodig |
| [08_rollen_en_gebruikers.sql](sql/08_rollen_en_gebruikers.sql) | Lokaal MIVB (SYSTEM) | rollen en demogebruikers | de rollen moeten bestaan voordat 09 er rechten aan kan geven |
| [09_grants.sql](sql/09_grants.sql) | MIVB project | objectrechten per rol | heeft de views uit 06 en de rollen uit 08 nodig |

Het laadscript start je in PowerShell vanuit de projectmap. Het vraagt het
wachtwoord van MIVB. `-ExecutionPolicy Bypass` is nodig omdat Windows anders
het uitvoeren van een niet-ondertekend script kan blokkeren:

```powershell
powershell -ExecutionPolicy Bypass -File .\load\laden.ps1
```

Alle scripts zijn herhaalbaar. Let op twee afhankelijkheden:

- `04_transformatie.sql` maakt de tabellen eerst leeg, ook favorieten en storingen.
- `08_rollen_en_gebruikers.sql` verwijdert de rollen en maakt ze opnieuw aan;
  voer daarna altijd `09_grants.sql` opnieuw uit.

### Enkel de structuur, zonder data

Om de structuur op te bouwen zonder de dataset te downloaden, sla je `laden.ps1`
en `04_transformatie.sql` over. Voer de andere scripts in dezelfde volgorde uit:
00, 01, 02, 03, 05, 06, 07, 08, 09. Alle tabellen, constraints, sequences,
indexen, views, triggers, rollen en rechten bestaan dan, maar de tabellen zijn leeg.

Wat dan wel werkt:

- [02_controle_model.sql](tests/02_controle_model.sql): controleert de structuur via de data dictionary

Wat dan niet werkt, omdat het naar bestaande lijnen en haltes verwijst:

- de tests 01, 03, 04 en 05 geven geen of nulresultaten
- de tests 06 en 07 voegen storingen en favorieten toe voor lijn `1` en halte `0089`;
  zonder data mislukken die met ORA-02291 (parent key not found)

### Opnieuw beginnen van nul

Als SYSTEM ruim je alles op met:

```sql
DROP USER mivb_app CASCADE;
DROP USER mivb_beheerder CASCADE;
DROP USER mivb_analist CASCADE;
DROP ROLE app_publiek;
DROP ROLE beheerder;
DROP ROLE analist;
DROP USER mivb CASCADE;
```

Sluit eerst elke sessie van die gebruikers: de connectie **MIVB project** in VS Code
(Disconnect) en elke open SQL*Plus-sessie van een demogebruiker. Anders faalt
`DROP USER` met ORA-01940 (cannot drop a user that is currently connected).

Daarna begin je opnieuw bij `00_users_en_rollen.sql`.

## Tests

Bij elke bouwstap hoort een controlescript in [tests/](tests/), uit te voeren als MIVB
met F5:

| Script | Na | Controleert |
|---|---|---|
| [01_controle_staging.sql](tests/01_controle_staging.sql) | laden.ps1 | aantallen en inhoud van de staging-tabellen |
| [02_controle_model.sql](tests/02_controle_model.sql) | 03_sequences | tabellen en constraints via de data dictionary |
| [03_controle_transformatie.sql](tests/03_controle_transformatie.sql) | 04_transformatie | aantallen staging tegenover model, omzettingen |
| [04_performantie_indexen.sql](tests/04_performantie_indexen.sql) | 05_indexen | uitvoeringsplan en tijd zonder en met index |
| [05_controle_views.sql](tests/05_controle_views.sql) | 06_views | resultaten van de views |
| [06_controle_triggers.sql](tests/06_controle_triggers.sql) | 07_triggers | eindtijd en auditlog (met ROLLBACK) |
| [07_controle_security.sql](tests/07_controle_security.sql) | 09_grants | rechten per demogebruiker |

### De securitytest

De securitytest logt in als elke demogebruiker en toont per stap het verwachte
resultaat (OK, ORA-01031 of ORA-00942). Hij werkt met F5 in VS Code of in SQL*Plus:

```powershell
sqlplus /nolog "@tests/07_controle_security.sql"
```

- Het wachtwoord van MIVB wordt een keer gevraagd via `&&mivb_pw`. In SQL*Plus is
  het **zichtbaar** tijdens het typen.
- De uitvoer wordt enkel in SQL*Plus ook bewaard in `load/logs/security_test.txt`.
  In VS Code geeft de SPOOL-regel SP2-0556; dat is onschuldig, de uitvoer staat
  dan in het venster Script Output.

## Demogebruikers

| Gebruiker | Rol | Mag |
|---|---|---|
| `mivb_app` | app_publiek | vertrekken en storingen lezen via views, gebruikers en favorieten beheren |
| `mivb_beheerder` | beheerder | storingen invoeren en oplossen, auditlog lezen |
| `mivb_analist` | analist | alles lezen behalve persoonsgegevens, niets wijzigen |

De demowachtwoorden staan bewust in [08_rollen_en_gebruikers.sql](sql/08_rollen_en_gebruikers.sql),
zodat de tests zonder extra stappen werken. In een echte omgeving hoort dat niet.

## Documentatie

- [docs/use_case.md](docs/use_case.md): de use case
- [docs/ontwerpkeuzes.md](docs/ontwerpkeuzes.md): elke keuze met de reden erachter
- [docs/datamodel.md](docs/datamodel.md): het fysieke datamodel (Mermaid, rendert op GitHub)
- [docs/erd_conceptueel.drawio](docs/erd_conceptueel.drawio): het conceptuele ERD in Barker-notatie (openen met draw.io)
- docs/erd_conceptueel.png: export van het conceptuele ERD *(nog toe te voegen)*
- [docs/bronnen.md](docs/bronnen.md): gebruikte bronnen
