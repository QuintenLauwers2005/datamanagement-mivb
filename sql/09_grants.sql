-- Objectrechten per rol volgens least privilege 
-- mogelijk via View in plaats van rechtstreeks op tabellen

-- zonder recht -> ORA-00942 (het object lijkt niet te bestaan)
-- wel SELECT, maar geen UPDATE

-- ---------------------------------------------------------------------
-- 1. app_publiek  (reisinfo-app)
-- ---------------------------------------------------------------------

-- Vertrekken & storingen alleen via views
GRANT SELECT ON v_vertrekken        TO app_publiek;
GRANT SELECT ON v_actieve_storingen TO app_publiek;

-- Publieke referentiedata
GRANT SELECT ON halte        TO app_publiek;
GRANT SELECT ON lijn         TO app_publiek;
GRANT SELECT ON vervoerstype TO app_publiek;

-- Gebruikersbeheer (GDPR: recht op vergetelheid via DELETE + CASCADE)
GRANT SELECT, INSERT, DELETE ON gebruiker TO app_publiek;
GRANT UPDATE (naam)          ON gebruiker TO app_publiek;  -- enkel naam mag wijzigen
GRANT SELECT                 ON seq_gebruiker TO app_publiek; -- nodig voor DEFAULT

-- Favorieten
GRANT SELECT, INSERT, DELETE ON favoriete_halte TO app_publiek;

-- ---------------------------------------------------------------------
-- 2. beheerder  (storingen beheren)
-- ---------------------------------------------------------------------
GRANT SELECT, INSERT ON storing TO beheerder;

-- Kolomrechten: storing_id blijft ongewijzigd omdat de auditlog ernaar verwijst.
-- Wijzig je het id, dan hangen de logregels nergens meer aan.
-- start_tijd is een vast feit dat achteraf niet herschreven mag worden.
GRANT UPDATE (lijn_id, halte_id, omschrijving, status, eind_tijd)
      ON storing TO beheerder;

GRANT SELECT ON seq_storing TO beheerder;

-- Geen DELETE op storing → historiek blijft bewaard (status = OPGELOST)

GRANT SELECT ON storing_log TO beheerder;      -- alleen lezen (trigger schrijft met definer rights)

-- Opzoeken van lijnen/haltes + actieve storingen
GRANT SELECT ON lijn                TO beheerder;
GRANT SELECT ON halte               TO beheerder;
GRANT SELECT ON v_actieve_storingen TO beheerder;

-- ---------------------------------------------------------------------
-- 3. analist  (alleen lezen – geen persoonsgegevens)
-- ---------------------------------------------------------------------
GRANT SELECT ON v_ritten_per_lijn_per_uur   TO analist;
GRANT SELECT ON v_vertrekken                TO analist;
GRANT SELECT ON v_actieve_dienst            TO analist;
GRANT SELECT ON vervoerstype                TO analist;
GRANT SELECT ON lijn                        TO analist;
GRANT SELECT ON halte                       TO analist;
GRANT SELECT ON rit                         TO analist;
GRANT SELECT ON doortocht                   TO analist;
GRANT SELECT ON dienstregeling              TO analist;
GRANT SELECT ON dienstregeling_uitzondering TO analist;
GRANT SELECT ON storing                     TO analist;
GRANT SELECT ON storing_log                 TO analist;

-- Bewust GEEN rechten op gebruiker en favoriete_halte