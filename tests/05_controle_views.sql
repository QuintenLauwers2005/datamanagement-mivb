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
