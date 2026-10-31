-- =====================================================================
-- 07_controle_security.sql
-- Test de rechten door in te loggen als elke demogebruiker.
--
-- Dit script schakelt tussen gebruikers met CONNECT. Het kan op twee
-- manieren uitgevoerd worden:
--
--   * In VS Code: open het in een worksheet en voer uit met F5.
--   * In SQL*Plus, in PowerShell vanuit de projectmap:
--         sqlplus /nolog "@tests/07_controle_security.sql"
--
-- Bij de eerste CONNECT wordt een keer het wachtwoord van MIVB gevraagd
-- (substitutievariabele &&mivb_pw). In SQL*Plus komt de uitvoer ook in
-- load\logs\security_test.txt. De script-runner van VS Code aanvaardt
-- dat relatieve pad niet (SP2-0556); dat is onschuldig, de uitvoer
-- staat dan in het venster Script Output.
--
-- Bij elke stap staat met PROMPT wat er verwacht wordt:
--   OK         -> moet lukken
--   ORA-00942  -> geen enkel recht: het object is onzichtbaar
--   ORA-01031  -> het object is zichtbaar, maar deze actie mag niet
-- Alles wordt teruggedraaid met ROLLBACK.
-- =====================================================================

SET ECHO ON
SET FEEDBACK ON
SET VERIFY OFF
SET LINESIZE 200
SET PAGESIZE 100
COLUMN grantee         FORMAT A12
COLUMN table_name      FORMAT A28
COLUMN column_name     FORMAT A14
COLUMN privilege       FORMAT A10
COLUMN lijn            FORMAT A5
COLUMN bestemming      FORMAT A20
COLUMN vertrektijd_gtfs FORMAT A8
COLUMN actie           FORMAT A7
COLUMN oude_status     FORMAT A10
COLUMN nieuwe_status   FORMAT A10
COLUMN gewijzigd_door  FORMAT A16

SPOOL load/logs/security_test.txt

-- geen ACCEPT: dat vraagt in VS Code niets en laat mivb_pw leeg.
-- && vraagt de waarde bij het eerste gebruik en onthoudt ze.
UNDEFINE mivb_pw
DEFINE db = "localhost:1521/XEPDB1"

-- =====================================================================
PROMPT
PROMPT ===== 1. Overzicht van de gegeven rechten (als MIVB) =====
-- =====================================================================
CONNECT mivb/"&&mivb_pw"@&db

SELECT grantee, table_name, privilege
FROM   user_tab_privs_made
WHERE  grantee IN ('APP_PUBLIEK', 'BEHEERDER', 'ANALIST')
ORDER  BY grantee, table_name, privilege;

-- kolomrechten (UPDATE op enkel bepaalde kolommen)
SELECT grantee, table_name, column_name, privilege
FROM   user_col_privs_made
ORDER  BY grantee, table_name, column_name;

-- =====================================================================
PROMPT
PROMPT ===== 2. De app (MIVB_APP, rol APP_PUBLIEK) =====
-- =====================================================================
CONNECT mivb_app/"Demo_App_1"@&db

PROMPT [verwacht: OK] vertrekken via de view
SELECT vertrektijd_gtfs, lijn, bestemming
FROM   mivb.v_vertrekken
WHERE  dienstdag = DATE '2026-03-18' AND halte_id = '0089' AND vertrek_sec >= 8 * 3600
ORDER  BY vertrek_sec
FETCH FIRST 3 ROWS ONLY;

PROMPT [verwacht: OK] gebruiker registreren en favoriete halte bewaren
INSERT INTO mivb.gebruiker (email, naam) VALUES ('reiziger@test.be', 'Reiziger');
INSERT INTO mivb.favoriete_halte (gebruiker_id, halte_id)
SELECT gebruiker_id, '0089' FROM mivb.gebruiker WHERE email = 'reiziger@test.be';

PROMPT [verwacht: OK] naam wijzigen (kolomrecht op naam)
UPDATE mivb.gebruiker SET naam = 'Reiziger Twee' WHERE email = 'reiziger@test.be';

PROMPT [verwacht: ORA-01031] e-mailadres wijzigen mag niet (geen kolomrecht)
UPDATE mivb.gebruiker SET email = 'ander@test.be' WHERE email = 'reiziger@test.be';

PROMPT [verwacht: ORA-00942] doortocht is enkel bereikbaar via de view
SELECT COUNT(*) FROM mivb.doortocht;

PROMPT [verwacht: ORA-00942] de auditlog is intern
SELECT COUNT(*) FROM mivb.storing_log;

ROLLBACK;

-- =====================================================================
PROMPT
PROMPT ===== 3. Een beheerder (MIVB_BEHEERDER, rol BEHEERDER) =====
-- =====================================================================
CONNECT mivb_beheerder/"Demo_Beheer_1"@&db

PROMPT [verwacht: OK] storing invoeren en oplossen
INSERT INTO mivb.storing (lijn_id, omschrijving) VALUES ('1', 'Test security: metro 1 onderbroken');
UPDATE mivb.storing SET status = 'OPGELOST' WHERE omschrijving LIKE 'Test security%';

PROMPT [verwacht: OK] de auditlog lezen: GEWIJZIGD_DOOR is nu MIVB_BEHEERDER
SELECT actie, oude_status, nieuwe_status, gewijzigd_door
FROM   mivb.storing_log
WHERE  storing_id = (SELECT storing_id FROM mivb.storing WHERE omschrijving LIKE 'Test security%')
ORDER  BY log_id;

PROMPT [verwacht: ORA-01031] storingen verwijderen mag niet
DELETE FROM mivb.storing WHERE omschrijving LIKE 'Test security%';

PROMPT [verwacht: ORA-01031] de starttijd wijzigen mag niet (geen kolomrecht)
UPDATE mivb.storing SET start_tijd = SYSTIMESTAMP WHERE omschrijving LIKE 'Test security%';

PROMPT [verwacht: ORA-01031] zelf in de auditlog schrijven mag niet
INSERT INTO mivb.storing_log (storing_id, actie) VALUES (1, 'DELETE');

PROMPT [verwacht: ORA-00942] gebruikersgegevens zijn onzichtbaar
SELECT COUNT(*) FROM mivb.gebruiker;

ROLLBACK;

-- =====================================================================
PROMPT
PROMPT ===== 4. Een analist (MIVB_ANALIST, rol ANALIST) =====
-- =====================================================================
CONNECT mivb_analist/"Demo_Analist_1"@&db

PROMPT [verwacht: OK] rapport ritten per uur
SELECT uur, aantal_ritten
FROM   mivb.v_ritten_per_lijn_per_uur
WHERE  dienstdag = DATE '2026-03-18' AND lijn_id = '1' AND uur BETWEEN 7 AND 9
ORDER  BY uur;

PROMPT [verwacht: OK] rechtstreeks op de tabellen lezen
SELECT COUNT(*) AS doortochten FROM mivb.doortocht;

PROMPT [verwacht: ORA-00942] persoonsgegevens zijn onzichtbaar
SELECT COUNT(*) FROM mivb.gebruiker;

PROMPT [verwacht: ORA-01031] een analist wijzigt niets
UPDATE mivb.lijn SET korte_naam = 'X' WHERE lijn_id = '1';

ROLLBACK;

-- =====================================================================
PROMPT
PROMPT ===== 5. REVOKE: een recht intrekken en terug geven =====
-- =====================================================================
CONNECT mivb/"&mivb_pw"@&db
REVOKE SELECT ON mivb.v_actieve_storingen FROM app_publiek;

CONNECT mivb_app/"Demo_App_1"@&db
PROMPT [verwacht: ORA-00942] na REVOKE is de view onzichtbaar voor de app
SELECT COUNT(*) FROM mivb.v_actieve_storingen;

CONNECT mivb/"&mivb_pw"@&db
GRANT SELECT ON mivb.v_actieve_storingen TO app_publiek;

CONNECT mivb_app/"Demo_App_1"@&db
PROMPT [verwacht: OK] na GRANT werkt het weer
SELECT COUNT(*) FROM mivb.v_actieve_storingen;

DISCONNECT
SPOOL OFF
EXIT
