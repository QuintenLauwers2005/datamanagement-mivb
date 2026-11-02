-- =====================================================================
-- 05_controle_views.sql
-- Uit te voeren als MIVB na 06_views.sql, als script (F5)
--
-- De dataset loopt van 16/03/2026 tot 12/04/2026. Daarom wordt getest
-- met woensdag 18 maart 2026 in plaats van vandaag.
-- =====================================================================

-- 1. Welke views bestaan er?
SELECT view_name, read_only FROM user_views ORDER BY view_name;

-- 2. Aantal actieve dienstregelingen per dag, voor de eerste twee weken.
--    Verwacht: een duidelijk patroon tussen weekdagen en weekend.
SELECT datum,
       TO_CHAR(datum, 'DY', 'NLS_DATE_LANGUAGE=DUTCH') AS dag,
       COUNT(*) AS diensten
FROM   v_actieve_dienst
WHERE  datum BETWEEN DATE '2026-03-16' AND DATE '2026-03-29'
GROUP  BY datum
ORDER  BY datum;

-- 3. De kernvraag van de app: de 10 volgende vertrekken aan Montgomery
--    op woensdag 18/03 vanaf 08:00
SELECT vertrektijd_gtfs, lijn, vervoerstype, bestemming, halte_naam_nl
FROM   v_vertrekken
WHERE  dienstdag   = DATE '2026-03-18'
AND    halte_id    = '0089'
AND    vertrek_sec >= 8 * 3600
ORDER  BY vertrek_sec
FETCH FIRST 10 ROWS ONLY;

-- 4. Nachtritten: GTFS-tijd na 24:00 tegenover het echte vertrekmoment
SELECT dienstdag,
       vertrektijd_gtfs,
       TO_CHAR(vertrekmoment, 'DD/MM/YYYY HH24:MI') AS echt_vertrekmoment,
       lijn, halte_naam_nl
FROM   v_vertrekken
WHERE  dienstdag = DATE '2026-03-18'
AND    vertrek_sec >= 24 * 3600
AND    halte_id IN (SELECT halte_id FROM halte WHERE locatietype = 0 FETCH FIRST 200 ROWS ONLY)
ORDER  BY vertrek_sec DESC
FETCH FIRST 5 ROWS ONLY;

-- 5. Gebruikt de view de index? EXPLAIN PLAN van query 3.
--    Verwacht: INDEX RANGE SCAN op IDX_DOORTOCHT_HALTE_VERTREK.
--    De view wordt "samengevoegd" met de query (view merging): Oracle
--    behandelt hem alsof je de joins zelf had uitgeschreven.
EXPLAIN PLAN FOR
SELECT vertrektijd_gtfs, lijn, bestemming
FROM   v_vertrekken
WHERE  dienstdag   = DATE '2026-03-18'
AND    halte_id    = '0089'
AND    vertrek_sec >= 8 * 3600
ORDER  BY vertrek_sec
FETCH FIRST 10 ROWS ONLY;

SELECT plan_table_output FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, NULL, 'BASIC +ROWS +COST'));

-- 6. Rapport van de analist: ritten per uur op lijn 1 op 18/03
SELECT uur, aantal_ritten
FROM   v_ritten_per_lijn_per_uur
WHERE  dienstdag = DATE '2026-03-18'
AND    lijn_id   = '1'
ORDER  BY uur;

-- 7. Actieve storingen: een teststoring toevoegen, bekijken, terugdraaien
INSERT INTO storing (lijn_id, omschrijving) VALUES ('1', 'Test: vertraging door technisch defect');
SELECT storing_id, lijn, halte_naam_nl, omschrijving FROM v_actieve_storingen;
ROLLBACK;

-- 8. WITH READ ONLY: wijzigen via een view moet GEWEIGERD worden
--    Verwachte fout: ORA-42399: cannot perform a DML operation on a read-only view
UPDATE v_actieve_storingen SET omschrijving = 'mag niet';
ROLLBACK;

-- 9 en 10: uitzonderingen op Paasmaandag 6 april 2026 (zie docs/use_case.md)
--    Beide queries delen dezelfde indeling van een dienst (WITH soort):
--      weekdagdienst = rijdt op maandag, niet op zondag
--      zondagsdienst = rijdt op zondag, niet op maandag
--      ander         = al de rest (bv. maandag en zondag allebei)
--    De verwachte aantallen komen uit de GTFS-bestanden (calendar.txt en
--    calendar_dates.txt); bevestig ze met een run.

-- 9. Welke soort diensten worden op 06/04 geschrapt (type 2) en welke
--    komen erbij (type 1)?
--    Verwacht: type 1 = 69 zondagsdiensten, type 2 = 99 weekdagdiensten.
WITH soort AS (
  SELECT service_id,
         CASE WHEN maandag = 1 AND zondag = 0 THEN 'weekdagdienst'
              WHEN zondag = 1 AND maandag = 0 THEN 'zondagsdienst'
              ELSE 'ander' END AS soort
  FROM   dienstregeling
)
SELECT u.uitzonderingstype, s.soort, COUNT(*) AS aantal
FROM   dienstregeling_uitzondering u
JOIN   soort s ON s.service_id = u.service_id
WHERE  u.datum = DATE '2026-04-06'
GROUP  BY u.uitzonderingstype, s.soort
ORDER  BY 1, 2;

-- 10. Wat maakt v_actieve_dienst ervan? Paasmaandag naast een gewone
--     zondag (22/03) en een gewone maandag (30/03).
--     Verwacht: 22/03 = 69 zondagsdiensten, 30/03 = 75 weekdagdiensten,
--     06/04 = 69 zondagsdiensten: Paasmaandag rijdt als een zondag.
--
--     Waarom worden er op 06/04 99 weekdagdiensten geschrapt, terwijl er
--     op een gewone maandag maar 75 rijden? Volgens het weekpatroon zijn
--     er op elke maandag in de periode 99 weekdagdiensten geldig, maar
--     calendar_dates schrapt er ook op een gewone maandag al 24 (op 30/03
--     bijvoorbeeld). Op 06/04 worden ze alle 99 geschrapt. Voor die 24 had
--     het schrappen dus geen extra effect tegenover een gewone maandag.
WITH soort AS (
  SELECT service_id,
         CASE WHEN maandag = 1 AND zondag = 0 THEN 'weekdagdienst'
              WHEN zondag = 1 AND maandag = 0 THEN 'zondagsdienst'
              ELSE 'ander' END AS soort
  FROM   dienstregeling
)
SELECT a.datum, s.soort, COUNT(*) AS aantal
FROM   v_actieve_dienst a
JOIN   soort s ON s.service_id = a.service_id
WHERE  a.datum IN (DATE '2026-03-22', DATE '2026-03-30', DATE '2026-04-06')
GROUP  BY a.datum, s.soort
ORDER  BY 1, 2;
