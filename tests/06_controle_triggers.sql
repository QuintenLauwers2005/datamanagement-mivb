-- =====================================================================
-- 06_controle_triggers.sql
-- Uit te voeren als MIVB na 07_triggers.sql, als script (F5)
-- Alles wordt op het einde teruggedraaid met ROLLBACK.
-- =====================================================================

-- 1. Welke triggers bestaan er?
SELECT trigger_name, trigger_type, triggering_event, table_name, status
FROM   user_triggers
ORDER  BY trigger_name;

-- 2. Drie teststoringen toevoegen -> 3 logregels met actie INSERT
INSERT INTO storing (lijn_id, omschrijving)  VALUES ('1',    'Test A: metro 1 onderbroken');
INSERT INTO storing (halte_id, omschrijving) VALUES ('0089', 'Test B: lift buiten dienst');
INSERT INTO storing (lijn_id, omschrijving)  VALUES ('44',   'Test C: tram 44 vertraagd');

-- 3. Storing A oplossen ZONDER eindtijd mee te geven.
--    De BEFORE-trigger vult de eindtijd in; zonder trigger zou de
--    constraint ck_storing_eind deze UPDATE weigeren.
UPDATE storing SET status = 'OPGELOST' WHERE omschrijving LIKE 'Test A%';

SELECT storing_id, omschrijving, status,
       TO_CHAR(start_tijd, 'HH24:MI:SS') AS start_tijd,
       TO_CHAR(eind_tijd,  'HH24:MI:SS') AS eind_tijd
FROM   storing
WHERE  omschrijving LIKE 'Test%'
ORDER  BY storing_id;

-- 4. Rij-trigger: één UPDATE die TWEE rijen wijzigt -> TWEE logregels.
--    Een statement-trigger zou hier maar één keer uitgevoerd worden.
UPDATE storing SET status = 'OPGELOST' WHERE omschrijving LIKE 'Test B%' OR omschrijving LIKE 'Test C%';

-- 5. Storing C verwijderen: de storing verdwijnt, de log blijft
--    (storing_log heeft bewust geen foreign key naar storing)
DELETE FROM storing WHERE omschrijving LIKE 'Test C%';

-- 6. De volledige auditlog van deze test
--    Verwacht: 3x INSERT, 1x UPDATE (A), 2x UPDATE (B en C), 1x DELETE (C)
SELECT l.log_id, l.storing_id, l.actie, l.oude_status, l.nieuwe_status,
       l.gewijzigd_door, TO_CHAR(l.gewijzigd_op, 'HH24:MI:SS') AS tijdstip,
       CASE WHEN s.storing_id IS NULL THEN 'verwijderd' ELSE 'bestaat' END AS storing
FROM   storing_log l
LEFT JOIN storing s ON s.storing_id = l.storing_id
ORDER  BY l.log_id;

-- 7. Alles terugdraaien: ook de logregels verdwijnen, want ze horen
--    bij dezelfde transactie
ROLLBACK;

SELECT COUNT(*) AS logregels_na_rollback FROM storing_log;
