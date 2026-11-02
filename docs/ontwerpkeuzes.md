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
- **Gaten in de praktijk:** de eerste teststoring kreeg storing_id 21. Een gefaalde insert gebruikt toch een nummer (ROLLBACK geeft het niet terug), en na een herstart van de database waren de 20 gecachte nummers verloren.

## Transformatie (sql/04_transformatie.sql)

- **Van staging naar model met INSERT ... SELECT**, met de omzetting naar de juiste datatypes in de SELECT. Fouten in de data komen zo als duidelijke Oracle-fout boven, in plaats van stil verkeerde waarden in te laden.
- **Tijden:** `'HH:MM:SS'` wordt `uur*3600 + minuut*60 + seconde`. LPAD maakt eerst van `4:26:00` een `04:26:00`, zodat SUBSTR op vaste posities kan werken.
- **Decimaalteken:** de coördinaten gebruiken een punt. Met Belgische instellingen verwacht Oracle een komma, daarom zet het script `NLS_NUMERIC_CHARACTERS` voor de sessie vast.
- **Vertalingen:** gekoppeld via de originele tekst (`field_value`). `MAX(translation)` met GROUP BY garandeert één vertaling per naam, zodat de join geen dubbele haltes kan opleveren. Een ontbrekende vertaling blijft NULL: "geen vertaling bekend" is iets anders dan "de Nederlandse naam is gelijk aan de Franse". De views vullen het op met COALESCE.
- **Haltes in twee stappen:** eerst alle haltes zonder station, daarna `station_id` invullen met een UPDATE. Bij de zelfverwijzing moet het station al bestaan voor een perron ernaar kan verwijzen; zo speelt de volgorde van de rijen geen rol.
- **Herhaalbaar:** het script maakt de tabellen eerst leeg, kinderen voor ouders. `doortocht` met TRUNCATE (snel, geen undo, kan omdat geen enkele tabel ernaar verwijst); de andere met DELETE, omdat TRUNCATE niet mag op een tabel waarnaar een foreign key verwijst.
- **Geen `APPEND`-hint voor doortocht:** een direct-path insert wordt door Oracle genegeerd zolang er foreign keys op de tabel staan. Constraints tijdelijk uitschakelen zou sneller zijn, maar dan controleert de database de data niet bij het laden.
- **Indexen op doortocht herbouwen na het laden** (`ALTER INDEX ... REBUILD`): tijdens het laden groeien ze rij per rij met half gevulde blokken. Gemeten: pk_doortocht van 104 naar 56 MB.
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
| A. Geen index | TABLE ACCESS FULL op doortocht, HASH JOIN, WINDOW SORT | 2648 | 1,04 s |
| B. Index op halte_id | INDEX RANGE SCAN, daarna sorteren van alle ±540 doortochten (WINDOW SORT) | 327 | 0,09 s |
| C. Index op (halte_id, vertrek_sec) | INDEX RANGE SCAN zonder sortering, stopt na 10 rijen (WINDOW NOSORT STOPKEY); NESTED LOOPS via PK_RIT | 34 | < 0,01 s |

- **B → C:** bij B haalt Oracle alle doortochten van de halte op en sorteert ze; bij C staan ze al in volgorde in de index en stopt Oracle na 10 rijen (STOPKEY). Dit toont dat de volgorde van de kolommen in de index ertoe doet.
- **Ook de join verandert:** bij A en B joint Oracle met RIT via een HASH JOIN (full scan van 73.322 ritten), omdat het ±540 rijen verwacht. Bij C zijn het er nog 10, en kiest de optimizer NESTED LOOPS met een opzoeking per rit via PK_RIT. De optimizer kiest zijn aanpak op basis van het verwachte aantal rijen.
- **Tijden:** zonder index lijkt 1 s voor 50 zoekopdrachten nog snel, omdat de tabel volledig in het geheugen zit. Het verschil zit in de kost (factor 78) en in schaalbaarheid: met veel gelijktijdige gebruikers betekent A een full scan van 1,5 miljoen rijen per zoekopdracht.

Grootte: tabel doortocht 72 MB, idx_doortocht_halte_vertrek 37 MB, pk_doortocht 104 MB na het laden en 56 MB na `ALTER INDEX ... REBUILD`.
- Het grootste deel van het verschil komt door het laden: de PK bestond al en groeide rij per rij, met half gevulde blokken na elke splitsing. De andere index werd achteraf in één keer gebouwd en is daardoor compact. Daarom herbouwt 04_transformatie.sql de indexen op doortocht na het laden.
- Het resterende verschil (56 tegenover 37 MB) komt door de lange natuurlijke sleutel (rit_id, tot 18 tekens). Surrogaatsleutels zouden naar schatting 35–45 MB besparen; bewust niet gedaan, omdat dat ruim binnen de limieten valt en de import eenvoudiger houdt.

### Uitvoeringsplan van de kernquery via v_vertrekken (D5)

Dezelfde kernquery, maar nu via de view `v_vertrekken` (halte 0089, 18/03, vanaf 8:00).

**Wat ik zag.** EXPLAIN PLAN koos een plan zonder de kernindex (plan hash 2578046037, kost 510): Oracle begon bij `v_actieve_dienst`, zocht alle ritten van die diensten via `IDX_RIT_SERVICE` en controleerde per rit via `PK_DOORTOCHT` of hij langs halte 0089 komt.

**Hoe ik de oorzaak zocht.**
- *Nieuwe statistieken?* `USER_TABLES.LAST_ANALYZED` toonde dat de automatische statistiekenjob van Oracle (onderhoudsvenster van zaterdag 31/10) de tabellen opnieuw geanalyseerd had, met nieuwe histogrammen op o.a. `RIT.SERVICE_ID`. Met `DBMS_STATS.RESTORE_TABLE_STATS` de statistieken van 28/10 teruggezet: hetzelfde plan. De nieuwe statistieken waren dus niet de oorzaak.
- *Ontbreekt de index?* Nee: `USER_INDEXES` toont hem als VALID en VISIBLE.
- *Kiest de optimizer bewust?* Ja: met een hint (`INDEX(v_vertrekken.d idx_doortocht_halte_vertrek)`) gebruikt het plan de index, maar met een hogere geschatte kost (580 tegenover 510).

**De oorzaak: een verkeerde schatting in `v_actieve_dienst`.** Het werkelijke plan (`DBMS_XPLAN.DISPLAY_CURSOR` met `ALLSTATS LAST`) toont geschatte (E-Rows) naast echte (A-Rows) aantallen:

| Stap | Geschat | Echt |
|---|---|---|
| diensten volgens het weekpatroon (filter met `DECODE` op de weekdag) | 1 | 90 |
| `v_actieve_dienst` (na uitzonderingen) | 13 | 75 |

Oracle kan uit de statistieken niet afleiden hoeveel diensten er op een bepaalde weekdag rijden: de `DECODE` verbergt dat. Met 13 diensten lijkt de weg via `IDX_RIT_SERVICE` goedkoop; met de echte 75 zijn dat ±18.000 ritten om te controleren.

**De meting.** Beide plannen voor 50 haltes, tweede ronde: zonder hint 0,15 s, met hint 0,16 s, telkens 480 rijen. Geen verschil.

**Waarom geen verschil: een adaptief plan.** Het werkelijke plan (plan hash 3025061342) is een *adaptive plan*. Op drie plaatsen telt een STATISTICS COLLECTOR tijdens de uitvoering het echte aantal rijen. Omdat er 75 diensten kwamen in plaats van 13, schakelde Oracle om: de weg via `IDX_RIT_SERVICE` werd niet gebruikt, wel `IDX_DOORTOCHT_HALTE_VERTREK`, een full scan van RIT en HASH JOINs. Het plan uit EXPLAIN PLAN is dus nooit uitgevoerd.

**Besluiten.**
- EXPLAIN PLAN is een voorspelling vooraf. Wat er echt gebeurt, toont pas `DISPLAY_CURSOR` met `ALLSTATS LAST`; een lagere kost op papier is geen sneller plan. Meten blijft nodig.
- Via de view duurt de kernquery 0,15 s voor 50 haltes, tegenover < 0,01 s in situatie C rechtstreeks op de tabellen. Het verschil zit niet in de index, maar in `v_actieve_dienst`, die bij elke vraag de datums (`CONNECT BY`), weekdagen en uitzonderingen opnieuw berekent.
- De verkeerde schatting blijft bestaan; het adaptieve plan vangt ze hier op, maar dat is niet gegarandeerd bij andere queries. Mogelijke verbetering, bewust niet uitgevoerd: de actieve diensten per datum vooraf berekenen in een tabel of materialized view (±28 dagen × 75 diensten). Die heeft echte statistieken, zodat de schatting klopt, en hoeft niet bij elke vraag opnieuw berekend te worden.
- Bijkomende controle van de view-logica: aan halte 0089 zijn er 462 doortochten, waarvan 231 overblijven na de controle op een volgende halte. Montgomery is het eindpunt van tram 39 en 44: de helft zijn aankomsten, waar je niet meer kan opstappen, en die laat de view terecht weg.
- Voor `DISPLAY_CURSOR` moet MIVB de cursor cache (`v$sql`) kunnen lezen. Daarvoor kreeg MIVB tijdelijk `SELECT_CATALOG_ROLE` (als SYSTEM), en daarna weer ingetrokken: least privilege, ook voor de eigenaar.

## Views (sql/06_views.sql)

- **Waarom views:** ze verbergen de complexiteit van het model. De app hoeft niet te weten hoe dienstregelingen, uitzonderingen en seconden sinds middernacht werken. Ze zijn ook de basis voor de beveiliging: gebruikers krijgen rechten op views, niet op de tabellen.
- **Vier views:**
  - `v_actieve_dienst`: rekent calendar (periode + weekdagen) en calendar_dates (uitzonderingen) om naar een lijst (datum, service_id). Bouwsteen voor de andere views.
  - `v_vertrekken`: hoofdview van de app, alle vertrekken per halte en dienstdag met lijn, bestemming en echt vertrekmoment.
  - `v_ritten_per_lijn_per_uur`: rapport voor de analist.
  - `v_actieve_storingen`: lopende storingen met leesbare namen, zonder de interne historiek.
- **Geen view "vertrekken van vandaag":** de dataset loopt van 16/03 tot 12/04/2026, dus een filter op SYSDATE zou nu niets tonen. De views werken voor elke datum; de app geeft de datum mee. In een echte omgeving wordt de GTFS-feed wekelijks vernieuwd, en valt vandaag altijd binnen de periode.
- **Weekdag via `datum - TRUNC(datum, 'IW')`:** geeft 0 (maandag) tot 6 (zondag), onafhankelijk van de taalinstellingen. `TO_CHAR(datum, 'D')` hangt af van NLS_TERRITORY: in België is maandag 1, in de VS is zondag 1.
- **Datums genereren met `CONNECT BY LEVEL`:** één rij per dag tussen de vroegste start- en laatste einddatum, zonder een aparte kalendertabel.
- **UNION in plaats van UNION ALL** in v_actieve_dienst: een dienst die volgens de weekdagen rijdt en ook als extra dag vermeld staat, mag maar één keer voorkomen.
- **Eindhalte weggelaten in v_vertrekken:** de laatste halte van een rit is een aankomst, geen vertrek. Bij de eerste test toonde Montgomery trams 39 en 44 met bestemming MONTGOMERY: ritten die daar eindigen. Een doortocht telt enkel als vertrek als er voor dezelfde rit een doortocht met een hoger volgnummer bestaat (`EXISTS`); die controle gebruikt de primaire sleutel (rit_id, volgnummer), zichtbaar als INDEX RANGE SCAN op PK_DOORTOCHT in het plan. Een eerste versie gebruikte `NOT EXISTS` en hield daardoor net enkel de eindhaltes over; de controlequery toonde dat meteen.
- **Echt vertrekmoment = dienstdag + vertrek_sec / 86400:** GTFS-tijden tellen vanaf het begin van de dienstdag. 27:58 op 18/03 wordt zo correct 19/03 om 03:58.
- **De app filtert op vertrek_sec, niet op vertrekmoment:** vertrekmoment is een berekende kolom, en een voorwaarde daarop kan de index op (halte_id, vertrek_sec) niet gebruiken.
- **View merging, maar niet overal:** v_vertrekken wordt door de optimizer samengevoegd met de query, waardoor de index op (halte_id, vertrek_sec) gebruikt wordt. v_actieve_dienst niet: een view met UNION en CONNECT BY kan niet uitgeschreven worden en wordt apart berekend (VIEW V_ACTIEVE_DIENST in het plan). Daardoor moet Oracle alle ±540 doortochten van de halte ophalen en sorteren (kost 570, tegenover 34 zonder dienstregeling in test C, en 2648 zonder index). Mogelijke verbetering: v_actieve_dienst als materialized view opslaan, want die verandert enkel bij een nieuwe import.
- **WITH READ ONLY:** via de views kan niemand data wijzigen. Wijzigingen gebeuren enkel rechtstreeks op de tabellen, door wie daar rechten voor heeft.
- **v_ritten_per_lijn_per_uur is geen materialized view:** het rapport aggregeert over 1,5 miljoen doortochten en duurt een tot enkele seconden. Voor een rapport is dat aanvaardbaar. Een materialized view zou het resultaat opslaan en enkel bij een nieuwe import verversen; dat is het alternatief als het rapport vaak opgevraagd wordt.
- **Beperking, bewust niet opgelost:** net na middernacht moet de app eigenlijk twee dienstdagen combineren (de nachtritten van gisteren met tijden > 24:00, en de eerste ritten van vandaag). De view maakt dat mogelijk, maar de logica hoort in de query van de app.

## Triggers (sql/07_triggers.sql)

- **Twee triggers op storing**, allebei rij-triggers (FOR EACH ROW):
  - `trg_storing_eindtijd` (BEFORE UPDATE OF status): vult de eindtijd in wanneer een storing op OPGELOST gezet wordt, en maakt ze weer leeg bij heropenen.
  - `trg_storing_audit` (AFTER INSERT OR UPDATE OR DELETE): schrijft elke wijziging met oude en nieuwe status weg in storing_log.
- **BEFORE voor de eindtijd:** enkel in een BEFORE-trigger kan :NEW nog aangepast worden voor de rij weggeschreven wordt. De constraint ck_storing_eind eist een eindtijd bij een opgeloste storing; dankzij de trigger volstaat het dat de beheerder enkel de status wijzigt. De constraint blijft de echte garantie, de trigger maakt het gebruiksvriendelijk.
- **AFTER voor de audit:** de log wordt pas geschreven als de wijziging zelf gelukt is, en ziet de definitieve waarden (ook de eindtijd die de BEFORE-trigger invulde).
- **Rij-trigger en geen statement-trigger:** een statement-trigger wordt maar één keer per SQL-statement uitgevoerd en kent :OLD en :NEW niet. Een UPDATE van twee storingen tegelijk moet twee logregels opleveren (getest in tests/06_controle_triggers.sql).
- **Eén trigger voor drie acties:** INSERTING, UPDATING en DELETING bepalen de actie. Bij INSERT is :OLD leeg, bij DELETE :NEW, vandaar `COALESCE(:NEW.storing_id, :OLD.storing_id)`.
- **DEFAULT-waarden doen de rest:** log_id (sequence), gewijzigd_door (USER) en gewijzigd_op (SYSTIMESTAMP) worden niet door de trigger ingevuld. USER is de gebruiker die de wijziging uitvoert, niet de eigenaar van de trigger: zo zie je welke beheerder iets veranderde.
- **Log in dezelfde transactie:** bij een ROLLBACK verdwijnt de logregel samen met de wijziging. Zo wordt enkel gelogd wat echt gebeurd is. Alternatief: een autonomous transaction (PRAGMA AUTONOMOUS_TRANSACTION) zou ook pogingen loggen die teruggedraaid worden; dat is nuttig voor beveiligingsaudits, maar hier niet gewenst.
- **Tijden in UTC:** SYSTIMESTAMP geeft de tijd van de databaseserver, en die draait in UTC (de test toonde 14:43 terwijl het in België 15:43 was). Bewust zo gelaten: opslaan in UTC en pas bij weergave omzetten naar Europe/Brussels voorkomt verwarring bij de overgang tussen zomer- en wintertijd. Omzetten kan met `FROM_TZ(gewijzigd_op, 'UTC') AT TIME ZONE 'Europe/Brussels'`.
- **Geen foreign key van storing_log naar storing:** na een DELETE blijft de log bestaan, ook de regel die de verwijdering zelf vastlegt.

## Security (sql/08_rollen_en_gebruikers.sql en sql/09_grants.sql)

- **Drie rollen, drie demogebruikers:**

| Rol | Gebruiker | Wie | Mag |
|---|---|---|---|
| app_publiek | mivb_app | de reisinfo-app | vertrekken en actieve storingen lezen (via views), haltes en lijnen lezen, gebruikers registreren/verwijderen, naam wijzigen, favorieten bewaren |
| beheerder | mivb_beheerder | medewerker storingen | storingen invoeren en wijzigen (niet verwijderen), auditlog lezen, lijnen en haltes opzoeken |
| analist | mivb_analist | rapportering | alles lezen behalve persoonsgegevens, niets wijzigen |

- **Twee scripts, twee gebruikers:** rollen en gebruikers aanmaken vraagt systeemprivileges (CREATE ROLE, CREATE USER), dus dat doet SYSTEM. Objectrechten geeft MIVB, de eigenaar van de objecten. MIVB zelf heeft geen DBA-rechten.
- **Rollen in plaats van rechten per gebruiker:** een tweede beheerder krijgt met één `GRANT beheerder TO ...` alle juiste rechten, en een wijziging aan de rol geldt meteen voor iedereen met die rol.
- **Least privilege:** elke rol krijgt enkel wat zijn taak vraagt. De demogebruikers hebben als systeemprivilege enkel CREATE SESSION, en geen QUOTA: ze bezitten zelf niets.
- **Views als beveiligingslaag:** de app krijgt geen rechten op doortocht, rit of dienstregeling, enkel op v_vertrekken. Ze kan de logica (actieve dienst, eindhalte weglaten) dus niet omzeilen, en ziet enkel de kolommen die de view toont.
- **Kolomrechten:** de app mag van gebruiker enkel de naam wijzigen, niet het e-mailadres. De beheerder mag storing_id en start_tijd van een storing niet wijzigen.
- **Geen DELETE op storing voor de beheerder:** een storing wordt opgelost, niet verwijderd, zodat de historiek bewaard blijft.
- **Auditlog niet te vervalsen:** de beheerder mag storing_log lezen, maar niet schrijven. De trigger schrijft erin met de rechten van zijn eigenaar (definer rights), dus de beheerder heeft geen INSERT-recht nodig. `gewijzigd_door` toont toch de beheerder, omdat USER de ingelogde gebruiker is.
- **SELECT op de sequences:** wie een rij toevoegt in een tabel met `DEFAULT seq.NEXTVAL`, moet SELECT hebben op die sequence. Daarom krijgt app_publiek seq_gebruiker en beheerder seq_storing.
- **Privacy:** de analist ziet gebruiker en favoriete_halte niet: e-mailadressen zijn persoonsgegevens die hij voor rapporten niet nodig heeft. De app mag een gebruiker verwijderen (recht op vergetelheid, GDPR); de favorieten verdwijnen mee via ON DELETE CASCADE.
- **ORA-00942 tegenover ORA-01031:** zonder enig recht op een object meldt Oracle dat het niet bestaat (ORA-00942), zodat een gebruiker zelfs niet te weten komt welke tabellen er zijn. Met SELECT maar zonder bv. UPDATE volgt ORA-01031 (insufficient privileges).
- **Objecten met schemanaam (mivb.v_vertrekken):** de andere gebruikers verwijzen naar de objecten met de naam van het schema ervoor. Alternatieven zijn synoniemen, of `ALTER SESSION SET CURRENT_SCHEMA = mivb` bij het inloggen; voor drie demogebruikers niet nodig.
- **Demowachtwoorden in het script:** bewust, zodat de tests zonder extra stappen werken. In een echte omgeving horen wachtwoorden niet in een script, en zou het app-account bijvoorbeeld via een wallet inloggen.

## Securitytest (`07_controle_security.sql`)

Het script logt achtereenvolgens in als elke demogebruiker (`mivb_app`, `mivb_beheerder` en `mivb_analist`) en controleert per stap of de verwachte uitkomst optreedt: **OK** (actie mag), **ORA-01031** (object is zichtbaar maar de actie mag niet) of **ORA-00942** (geen enkel recht → object is onzichtbaar).

In plaats van `ACCEPT ... HIDE` gebruikt het script de substitutievariabele `&&mivb_pw`. Het voordeel is dat SQL*Plus het wachtwoord slechts één keer vraagt en daarna hergebruikt bij elke `CONNECT`. Het nadeel is dat het wachtwoord in de SQL*Plus-sessie zichtbaar blijft (in tegenstelling tot `HIDE`).

Bij de `REVOKE` en `GRANT` in sectie 5 staat `mivb.` voor de viewnaam (`mivb.v_actieve_storingen`). Dit is nodig omdat die statements als de eigenaar (MIVB) worden uitgevoerd, maar de objectnaam anders niet eenduidig is wanneer de huidige schema-context niet MIVB is.
