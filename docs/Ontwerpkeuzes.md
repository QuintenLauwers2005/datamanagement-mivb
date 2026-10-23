# Ontwerpkeuzes

Bij elke keuze: wat ik gekozen heb en waarom. 

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

## Te controleren tijdens de import

- Komen alle `service_id`'s uit `calendar_dates` ook voor in `calendar`? (In GTFS is dat niet verplicht. Zo niet: ook die in `dienstregeling` opnemen.)
- Bestaan alle `parent_station`-waarden als `stop_id` in `stops`?
