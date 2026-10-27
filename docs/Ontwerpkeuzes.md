# Ontwerpkeuzes

Bij elke keuze: wat ik gekozen heb en waarom. Aanvullen tijdens het bouwen.

## Dataset

- **Bron:** GTFS-dienstregeling van de MIVB (STIB/MIVB), gedownload via de Mobility Database (feed mdb-1088, versie van 17/03/2026, dienstregeling 16/03/2026 – 12/04/2026).
- **Waarom deze dataset:** echte, lokale data met een duidelijke relationele structuur. `stop_times` bevat ±1,56 miljoen rijen, genoeg om de impact van indexen meetbaar te maken.

## Wat ik overneem en wat niet

| GTFS-bestand | Keuze | Reden |
|---|---|---|
| routes, trips, stop_times, stops | Overgenomen | Kern van de use case |
| calendar, calendar_dates | Overgenomen | Nodig om te bepalen of een rit op een datum rijdt |
| translations | Verwerkt in `halte` (`naam_fr`, `naam_nl`) | Generieke vertaaltabel (EAV) is omslachtig om op te queryen; twee kolommen volstaan voor een tweetalige stad |
| agency | Weggelaten | Slechts één maatschappij: een tabel met één rij voegt niets toe |
| feed_info | Weggelaten (vermeld in documentatie) | Metadata over de export, geen applicatiedata |
| shapes | Weggelaten | Enkel nodig voor kaartweergave, valt buiten de use case |
| Lege kolommen (route_desc, route_url, stop_code, stop_desc, zone_id, stop_url) | Weggelaten | Bevatten geen data |
| pickup_type, drop_off_type, timepoint, block_id | Weggelaten | Niet nodig voor de use case |

## Datatypes

- **ID's als VARCHAR2, niet als NUMBER:** `stop_id` heeft voorloopnullen (`0089`) die als getal verloren gaan. `trip_id` lijkt een getal maar is een code: er wordt nooit mee gerekend.
- **Tijden als seconden sinds middernacht (NUMBER):** GTFS-tijden kunnen boven 24:00:00 gaan bij ritten na middernacht (bv. `25:10:00`). Een DATE of TIMESTAMP kan dat niet voorstellen. Seconden zijn bovendien makkelijk te vergelijken en te sorteren.
- **Datums als DATE:** GTFS levert `YYYYMMDD` als tekst; omgezet bij het importeren.
- **`route_type` naar een opzoektabel `vervoerstype`:** de codes 0/1/3 zijn betekenisloos zonder uitleg; een opzoektabel maakt het leesbaar en afdwingbaar via een foreign key.

## Eigen toevoegingen

- `gebruiker` en `favoriete_halte`: reizigers kunnen haltes bewaren (veel-op-veel via een koppeltabel).
- `storing`: beheerders melden storingen per lijn of halte. CHECK-constraint: minstens één van beide moet ingevuld zijn.
- `storing_log`: auditlog, gevuld door een trigger. **Bewust geen foreign key** naar `storing`: als een storing verwijderd wordt, moet de log bewaard blijven.

## Werkwijze import

- Eerst ruwe import in staging-tabellen (alle kolommen VARCHAR2), daarna transformatie naar het eigen model met INSERT ... SELECT. Zo faalt de import niet op datatypes en zijn importeren en modelleren gescheiden.

## Resultaten controle staging (tests/01_controle_staging.sql)

| Controle | Resultaat | Gevolg voor het datamodel |
|---|---|---|
| Aantal rijen | 86 lijnen, 2.752 haltes, 73.322 ritten, 1.559.649 doortochten, 339 dienstregelingen, 538 uitzonderingen | Alles volledig geladen (stop_times = 1.559.650 regels min de header) |
| Max. lengte codes | route_id 2, service_id 9, trip_id 18, stop_id 7, stop_name 35 | Lengtes: lijn_id VARCHAR2(10), service_id VARCHAR2(10), rit_id VARCHAR2(20), halte_id VARCHAR2(10), namen VARCHAR2(100). Kleine marge voor latere versies van de dataset |
| Hoogste volgnummer in een rit | 40 | NUMBER(3) volstaat |
| Doortochten na middernacht | 51.497, laatste vertrek om 27:58:00 | Bevestigt de keuze voor seconden sinds middernacht: een DATE kan 27:58 niet voorstellen. 27:58:00 = 100.680 s, dus NUMBER(6) volstaat |
| service_id's enkel in calendar_dates | 0 | Foreign key van dienstregeling_uitzondering naar dienstregeling kan zonder uitzonderingen |
| Ontbrekende parent_stations | 0 | Zelfverwijzende foreign key op halte kan |
| Doortochten met onbekende rit of halte | 0 / 0 | Alle foreign keys op doortocht kunnen afgedwongen worden |
| Haltes met voorloopnul | 238 | Bevestigt VARCHAR2 voor halte_id |
| Vertalingen | stop_name: 1.089 fr + 1.089 nl; route_long_name: 84 fr + 84 nl (van 86 lijnen); agency: genegeerd | Vertalingen hangen aan de naam (field_value), niet aan het id: veel haltes delen dezelfde naam (2.752 haltes, 1.089 namen). Koppelen via de naam. Zonder vertaling valt de Nederlandse naam terug op de Franse |

## Staging en import

- De GTFS-kolom `date` (calendar_dates) heet in staging `datum`, omdat DATE een gereserveerd woord is in Oracle.
- stop_times wordt geladen met SQL*Loader in `DIRECT=TRUE`-modus: direct path load schrijft rechtstreeks naar de datablokken en is veel sneller bij 1,5 miljoen rijen.
- De control files gebruiken `TRUNCATE`, zodat opnieuw laden geen dubbele rijen geeft.
