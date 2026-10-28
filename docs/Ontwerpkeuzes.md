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
| location_type | 2.439 haltes/perrons (0), 70 stations (1), 243 ingangen/uitgangen (2) | De eerste CHECK-constraint liet enkel 0 en 1 toe en weigerde daardoor de import. De constraint volgt nu de GTFS-specificatie (0–4), niet enkel de waarden die vandaag voorkomen, zodat een volgende versie van de dataset ook geldig blijft |
| Vertalingen | stop_name: 1.089 fr + 1.089 nl; route_long_name: 84 fr + 84 nl (van 86 lijnen); agency: genegeerd | Vertalingen hangen aan de naam (field_value), niet aan het id: veel haltes delen dezelfde naam (2.752 haltes, 1.089 namen). Koppelen via de naam. Zonder vertaling blijft naam_nl leeg (NULL); de views vallen dan terug op de Franse naam |

## Staging en import

- De GTFS-kolom `date` (calendar_dates) heet in staging `datum`, omdat DATE een gereserveerd woord is in Oracle.
- stop_times wordt geladen met SQL*Loader in `DIRECT=TRUE`-modus: direct path load schrijft rechtstreeks naar de datablokken en is veel sneller bij 1,5 miljoen rijen.
- De control files gebruiken `TRUNCATE`, zodat opnieuw laden geen dubbele rijen geeft.

## Datamodel (sql/02_model_tabellen.sql)

- **Natuurlijke sleutels voor de GTFS-tabellen.** De GTFS-codes zijn uniek en stabiel binnen één dataset en blijven dus de primaire sleutel. Surrogaatsleutels overwogen: ze zouden `doortocht` en de indexen erop ruwweg 20 à 30 MB kleiner maken, maar elke koppeling bij de import vraagt dan een extra join op de GTFS-code. Bij deze datasetgrootte weegt die winst niet op tegen de extra complexiteit.
- **Surrogaatsleutels voor de eigen tabellen** (gebruiker, storing, storing_log): daar bestaat geen natuurlijke code. Een e-mailadres kan veranderen en is daarom een UNIQUE-constraint, geen PK.
- **`lijn` krijgt `lange_naam_fr` en `lange_naam_nl`**, net zoals `halte`: de vertalingen bestaan voor beide.
- **Benoemde constraints** (pk_, fk_, uk_, ck_): een fout zoals `CK_STORING_DOEL violated` zegt meteen wat er mis is, en ze zijn herkenbaar in USER_CONSTRAINTS.
- **ON DELETE CASCADE enkel bij identificerende relaties** (rit → doortocht, dienstregeling → uitzondering, gebruiker → favoriete_halte): die rijen hebben geen betekenis zonder hun ouder. Bij de andere relaties niet: een lijn verwijderen waaraan nog ritten hangen moet geweigerd worden.
- **CHECK-constraints dwingen bedrijfsregels af in de database**, niet enkel in de applicatie: een storing heeft minstens een lijn of halte; een opgeloste storing heeft een eindtijd en een actieve niet; vertrek kan niet vóór aankomst liggen.
- **Foreign keys krijgen in Oracle geen automatische index** (PK en UNIQUE wel). Indexen op FK-kolommen zoals `doortocht.halte_id` komen bewust in 05_indexen.sql, zodat het effect meetbaar is.

## Sequences (sql/03_sequences.sql)

- **Sequence als DEFAULT van de id-kolom** (Oracle 12c+): een INSERT zonder id krijgt automatisch het volgende nummer, zonder trigger.
- **Waarom geen IDENTITY-kolom?** Die doet intern hetzelfde (Oracle maakt er zelf een sequence voor), maar een expliciete sequence is zichtbaar als apart object, kan door meerdere tabellen of scripts gebruikt worden en sluit aan bij de leerstof.
- **CACHE 20:** sneller omdat nummers vooraf in het geheugen klaarstaan. Gevolg: na een herstart kunnen er gaten in de nummering zijn. Geen probleem: een surrogaatsleutel moet uniek zijn, niet aaneensluitend.

## Transformatie (sql/04_transformatie.sql)

- **Van staging naar model met INSERT ... SELECT**, met de omzetting naar de juiste datatypes in de SELECT. Fouten in de data komen zo als duidelijke Oracle-fout boven, in plaats van stil verkeerde waarden in te laden.
- **Tijden:** `'HH:MM:SS'` wordt `uur*3600 + minuut*60 + seconde`. LPAD maakt eerst van `4:26:00` een `04:26:00`, zodat SUBSTR op vaste posities kan werken.
- **Decimaalteken:** de coördinaten gebruiken een punt. Met Belgische instellingen verwacht Oracle een komma, daarom zet het script `NLS_NUMERIC_CHARACTERS` voor de sessie vast.
- **Vertalingen:** gekoppeld via de originele tekst (`field_value`). `MAX(translation)` met GROUP BY garandeert één vertaling per naam, zodat de join geen dubbele haltes kan opleveren. Een ontbrekende vertaling blijft NULL: "geen vertaling bekend" is iets anders dan "de Nederlandse naam is gelijk aan de Franse". De views vullen het op met COALESCE.
- **Haltes in twee stappen:** eerst alle haltes zonder station, daarna `station_id` invullen met een UPDATE. Bij de zelfverwijzing moet het station al bestaan voor een perron ernaar kan verwijzen; zo speelt de volgorde van de rijen geen rol.
- **Herhaalbaar:** het script maakt de tabellen eerst leeg, kinderen voor ouders. `doortocht` met TRUNCATE (snel, geen undo, kan omdat geen enkele tabel ernaar verwijst); de andere met DELETE, omdat TRUNCATE niet mag op een tabel waarnaar een foreign key verwijst.
- **Geen `APPEND`-hint voor doortocht:** een direct-path insert wordt door Oracle genegeerd zolang er foreign keys op de tabel staan. Constraints tijdelijk uitschakelen zou sneller zijn, maar dan controleert de database de data niet bij het laden.
- **Statistieken verzamelen na het laden** (`DBMS_STATS.GATHER_SCHEMA_STATS`): de optimizer baseert zijn uitvoeringsplan op statistieken. Zonder actuele statistieken zijn de EXPLAIN PLAN-metingen bij de indexen niet betrouwbaar.

## Indexen (sql/05_indexen.sql)

- **Kernindex `idx_doortocht_halte_vertrek` op (halte_id, vertrek_sec)** voor de hoofdvraag van de app: de volgende vertrekken aan een halte.
  - halte_id eerst, omdat daarop met `=` gezocht wordt; vertrek_sec tweede, omdat daarop een bereik (`>=`) en de sortering slaan. Binnen één halte staan de tijden dan al gesorteerd in de index, zodat Oracle kan stoppen na 10 rijen zonder aparte SORT-stap.
  - Omgekeerde volgorde (vertrek_sec, halte_id) werkt veel slechter: binnen eenzelfde tijdstip staan alle haltes door elkaar.
  - Dient tegelijk als index op de foreign key `fk_doortocht_halte`, omdat halte_id de eerste kolom is.
- **Indexen op foreign keys:** Oracle maakt ze niet automatisch. Zonder index is een join op die kolom een full table scan, en bij een DELETE of UPDATE van de ouderrij vergrendelt Oracle de volledige kindtabel. Geen extra index waar de FK al de eerste kolom van een PK is (doortocht.rit_id, favoriete_halte.gebruiker_id, dienstregeling_uitzondering.service_id).
- **Bewust geen index** op haltenamen (2.752 rijen: een full scan is al snel), op vertrek_sec alleen, en op kolommen met weinig verschillende waarden (richting, status).
- **Prijs van een index:** extra opslag en tragere schrijfoperaties, omdat elke INSERT/UPDATE/DELETE ook de index moet bijwerken. Daarom enkel indexen die een concrete query uit de use case ondersteunen.

### Meting (tests/04_performantie_indexen.sql)

Dezelfde kernquery voor 50 haltes, tweede ronde gemeten (data al in het geheugen):

| Situatie | Toegangspad (EXPLAIN PLAN) | Geschatte kost | Tijd voor 50 zoekopdrachten |
|---|---|---|---|
| A. Geen index | _invullen_ | _invullen_ | _invullen_ |
| B. Index op halte_id | _invullen_ | _invullen_ | _invullen_ |
| C. Index op (halte_id, vertrek_sec) | _invullen_ | _invullen_ | _invullen_ |

Grootte: tabel doortocht _invullen_ MB, index idx_doortocht_halte_vertrek _invullen_ MB.
