-- =====================================================================
-- 04_performantie_indexen.sql
-- Uit te voeren als MIVB, NA 05_indexen.sql, als script (F5)
-- Duurt een halve minuut tot een minuut (de meting zonder index is traag).
--
-- Meet de kernquery van de app in drie situaties:
--   A. zonder index op doortocht.halte_id
--   B. met een index op enkel halte_id
--   C. met de samengestelde index (halte_id, vertrek_sec)
--
-- Per situatie:
--   * EXPLAIN PLAN: hoe Oracle de query wil uitvoeren (toegangspad en
--     geschatte kost volgens de optimizer)
--   * een tijdsmeting: dezelfde query voor 50 verschillende haltes
--
-- Op het einde staat de samengestelde index er weer, zoals in 05_indexen.sql.
-- =====================================================================

SET SERVEROUTPUT ON

-- Hulpprocedure voor de tijdsmeting (wordt op het einde verwijderd).
-- De query wordt twee keer uitgevoerd: de eerste ronde laadt de data in
-- het geheugen (buffer cache), enkel de tweede ronde wordt gemeten.
-- Zo vergelijken we de toegangspaden en niet het verschil tussen lezen
-- van schijf en lezen uit het geheugen.
CREATE OR REPLACE PROCEDURE meet_vertrekken (p_situatie IN VARCHAR2) IS
  v_start  PLS_INTEGER;
  v_rijen  PLS_INTEGER;
BEGIN
  FOR ronde IN 1 .. 2 LOOP
    v_rijen := 0;
    v_start := DBMS_UTILITY.GET_TIME;   -- in honderdsten van een seconde

    FOR h IN (SELECT halte_id FROM halte
              WHERE  locatietype = 0
              ORDER  BY halte_id
              FETCH FIRST 50 ROWS ONLY) LOOP
      -- de kernquery: de 10 volgende vertrekken vanaf 8:00
      FOR r IN (SELECT d.vertrek_sec, l.korte_naam, r.bestemming
                FROM   doortocht d
                JOIN   rit  r ON r.rit_id  = d.rit_id
                JOIN   lijn l ON l.lijn_id = r.lijn_id
                WHERE  d.halte_id = h.halte_id
                AND    d.vertrek_sec >= 8 * 3600
                ORDER  BY d.vertrek_sec
                FETCH FIRST 10 ROWS ONLY) LOOP
        v_rijen := v_rijen + 1;
      END LOOP;
    END LOOP;

    IF ronde = 2 THEN
      DBMS_OUTPUT.PUT_LINE(p_situatie || ': '
        || TO_CHAR((DBMS_UTILITY.GET_TIME - v_start) / 100, 'FM9990.00')
        || ' s voor 50 zoekopdrachten (' || v_rijen || ' rijen)');
    END IF;
  END LOOP;
END;
/

-- Vertrekpunt: beide varianten van de index weghalen
BEGIN
  FOR i IN (SELECT index_name FROM user_indexes
            WHERE index_name IN ('IDX_DOORTOCHT_HALTE', 'IDX_DOORTOCHT_HALTE_VERTREK')) LOOP
    EXECUTE IMMEDIATE 'DROP INDEX ' || i.index_name;
  END LOOP;
END;
/

-- =====================================================================
-- A. ZONDER index op halte_id
--    Verwacht: TABLE ACCESS FULL op DOORTOCHT (alle 1,5 miljoen rijen
--    lezen voor elke zoekopdracht) en een aparte SORT-stap.
-- =====================================================================
EXPLAIN PLAN FOR
SELECT d.vertrek_sec, l.korte_naam, r.bestemming
FROM   doortocht d
JOIN   rit  r ON r.rit_id  = d.rit_id
JOIN   lijn l ON l.lijn_id = r.lijn_id
WHERE  d.halte_id = '0089'
AND    d.vertrek_sec >= 8 * 3600
ORDER  BY d.vertrek_sec
FETCH FIRST 10 ROWS ONLY;

SELECT plan_table_output FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, NULL, 'BASIC +ROWS +COST'));

EXEC meet_vertrekken('A. Zonder index                 ')

-- =====================================================================
-- B. Index op enkel halte_id
--    Verwacht: INDEX RANGE SCAN, maar Oracle moet alle doortochten van
--    de halte ophalen en daarna nog sorteren op vertrek_sec.
-- =====================================================================
CREATE INDEX idx_doortocht_halte ON doortocht (halte_id);

EXPLAIN PLAN FOR
SELECT d.vertrek_sec, l.korte_naam, r.bestemming
FROM   doortocht d
JOIN   rit  r ON r.rit_id  = d.rit_id
JOIN   lijn l ON l.lijn_id = r.lijn_id
WHERE  d.halte_id = '0089'
AND    d.vertrek_sec >= 8 * 3600
ORDER  BY d.vertrek_sec
FETCH FIRST 10 ROWS ONLY;

SELECT plan_table_output FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, NULL, 'BASIC +ROWS +COST'));

EXEC meet_vertrekken('B. Index op halte_id            ')

DROP INDEX idx_doortocht_halte;

-- =====================================================================
-- C. Samengestelde index (halte_id, vertrek_sec)
--    Verwacht: INDEX RANGE SCAN die meteen op het juiste tijdstip begint
--    en de rijen al gesorteerd teruggeeft: Oracle kan stoppen na 10 rijen.
-- =====================================================================
CREATE INDEX idx_doortocht_halte_vertrek ON doortocht (halte_id, vertrek_sec);

EXPLAIN PLAN FOR
SELECT d.vertrek_sec, l.korte_naam, r.bestemming
FROM   doortocht d
JOIN   rit  r ON r.rit_id  = d.rit_id
JOIN   lijn l ON l.lijn_id = r.lijn_id
WHERE  d.halte_id = '0089'
AND    d.vertrek_sec >= 8 * 3600
ORDER  BY d.vertrek_sec
FETCH FIRST 10 ROWS ONLY;

SELECT plan_table_output FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, NULL, 'BASIC +ROWS +COST'));

EXEC meet_vertrekken('C. Index op (halte_id, vertrek_sec)')

-- =====================================================================
-- De prijs van een index: opslagruimte
-- =====================================================================
SELECT segment_name,
       segment_type,
       ROUND(bytes / 1024 / 1024, 1) AS mb
FROM   user_segments
WHERE  segment_name IN ('DOORTOCHT', 'PK_DOORTOCHT', 'IDX_DOORTOCHT_HALTE_VERTREK')
ORDER  BY segment_type DESC, segment_name;

-- Opruimen: de hulpprocedure hoort niet bij de databank
DROP PROCEDURE meet_vertrekken;
