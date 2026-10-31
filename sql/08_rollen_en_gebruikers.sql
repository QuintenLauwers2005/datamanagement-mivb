-- Uit te voeren als SYSTEM (connectie "Lokaal MIVB"), als script (F5)

--maakt 3 rollen en demogebruikers aan.
-- rechten op tabellen/views staan bij 09_grants 

-- dit script verwijdert demogebruikers en rollen
-- je moet hierna altijd grants opnieuw uitvoeren


-- bestaande objecten opruimen(herhaalbaar)
DECLARE
  TYPE t_namen IS TABLE OF VARCHAR2(30);
  v_users t_namen := t_namen('MIVB_APP', 'MIVB_BEHEERDER', 'MIVB_ANALIST');
  v_roles t_namen := t_namen('APP_PUBLIEK', 'BEHEERDER', 'ANALIST');
BEGIN
  FOR i IN 1 .. v_users.COUNT LOOP
    BEGIN
      EXECUTE IMMEDIATE 'DROP USER ' || v_users(i) || ' CASCADE';
    EXCEPTION
      WHEN OTHERS THEN
        IF SQLCODE != -1918 THEN RAISE; END IF; -- -1918 = user does not exist
    END;
  END LOOP;

  FOR i IN 1 .. v_roles.COUNT LOOP
    BEGIN
      EXECUTE IMMEDIATE 'DROP ROLE ' || v_roles(i);
    EXCEPTION
      WHEN OTHERS THEN
        IF SQLCODE != -1919 THEN RAISE; END IF; -- -1919 = role does not exist
    END;
  END LOOP;
END;
/

-- Rollen
CREATE ROLE app_publiek;   -- reisinfo-app
CREATE ROLE beheerder;     -- storingen invoeren/oplossen
CREATE ROLE analist;       -- alleen lezen (geen persoonsgegevens)

GRANT CREATE SESSION TO app_publiek, beheerder, analist;

-- Demogebruikers (geen QUOTA nodig)
CREATE USER mivb_app       IDENTIFIED BY "Demo_App_1";
CREATE USER mivb_beheerder IDENTIFIED BY "Demo_Beheer_1";
CREATE USER mivb_analist   IDENTIFIED BY "Demo_Analist_1";

GRANT app_publiek TO mivb_app;
GRANT beheerder   TO mivb_beheerder;
GRANT analist     TO mivb_analist;