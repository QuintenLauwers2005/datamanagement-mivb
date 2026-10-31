-- =====================================================================
-- 07_triggers.sql
-- Uit te voeren als MIVB, NA 06_views.sql, als script (F5)
--
-- Twee triggers op de tabel storing:
--   1. trg_storing_eindtijd (BEFORE, per rij): vult de eindtijd
--      automatisch in wanneer een storing opgelost wordt.
--   2. trg_storing_audit (AFTER, per rij): schrijft elke wijziging weg
--      in storing_log (auditlog).
--
-- Volgorde bij een UPDATE van een storing:
--   BEFORE-trigger (kan :NEW aanpassen)
--   -> constraints worden gecontroleerd (o.a. ck_storing_eind)
--   -> de rij wordt weggeschreven
--   -> AFTER-trigger (ziet de definitieve waarden)
--
-- Beide zijn rij-triggers (FOR EACH ROW): ze worden uitgevoerd voor elke
-- gewijzigde rij en hebben toegang tot de oude (:OLD) en nieuwe (:NEW)
-- waarden. Een statement-trigger (zonder FOR EACH ROW) wordt maar één
-- keer per SQL-statement uitgevoerd, hoeveel rijen er ook wijzigen, en
-- kent :OLD en :NEW niet. Voor een auditlog per storing is dat dus niet
-- bruikbaar.
--
-- CREATE OR REPLACE: het script is herhaalbaar.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Eindtijd automatisch invullen
--
-- Waarom BEFORE: enkel in een BEFORE-trigger kan je :NEW nog aanpassen
-- voor de rij weggeschreven wordt. De constraint ck_storing_eind eist
-- dat een OPGELOSTE storing een eindtijd heeft. Dankzij deze trigger
-- volstaat het dat de beheerder enkel de status aanpast.
-- ---------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_storing_eindtijd
BEFORE UPDATE OF status ON storing
FOR EACH ROW
BEGIN
  IF :NEW.status = 'OPGELOST' AND :OLD.status = 'ACTIEF' AND :NEW.eind_tijd IS NULL THEN
    -- storing opgelost: eindtijd = nu
    :NEW.eind_tijd := SYSTIMESTAMP;
  ELSIF :NEW.status = 'ACTIEF' AND :OLD.status = 'OPGELOST' THEN
    -- storing heropend: eindtijd weer leeg
    :NEW.eind_tijd := NULL;
  END IF;
END;
/

-- ---------------------------------------------------------------------
-- 2. Auditlog
--
-- Waarom AFTER: de log mag enkel geschreven worden als de wijziging zelf
-- gelukt is (alle constraints in orde), en ziet zo de definitieve waarden.
--
-- * INSERTING / UPDATING / DELETING: zeggen welke actie de trigger
--   uitlokte, zodat één trigger de drie acties afhandelt.
-- * Bij INSERT is er geen :OLD, bij DELETE geen :NEW (die zijn dan NULL).
--   Daarom COALESCE voor storing_id.
-- * log_id, gewijzigd_door en gewijzigd_op worden niet ingevuld: daar
--   zorgen de DEFAULT-waarden voor (seq_storing_log.NEXTVAL, USER en
--   SYSTIMESTAMP). USER is de gebruiker die de wijziging deed, niet de
--   eigenaar van de trigger.
-- * De log hoort bij dezelfde transactie: bij een ROLLBACK verdwijnen
--   de wijziging en de logregel samen. Dat is de bedoeling: er wordt
--   enkel gelogd wat echt gebeurd is.
-- ---------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_storing_audit
AFTER INSERT OR UPDATE OR DELETE ON storing
FOR EACH ROW
DECLARE
  v_actie storing_log.actie%TYPE;
BEGIN
  IF INSERTING THEN
    v_actie := 'INSERT';
  ELSIF UPDATING THEN
    v_actie := 'UPDATE';
  ELSE
    v_actie := 'DELETE';
  END IF;

  INSERT INTO storing_log (storing_id, actie, oude_status, nieuwe_status)
  VALUES (COALESCE(:NEW.storing_id, :OLD.storing_id), v_actie, :OLD.status, :NEW.status);
END;
/
