-- =====================================================================
-- 03_sequences.sql
-- Uit te voeren als MIVB, NA 02_model_tabellen.sql, als script (F5)
--
-- Sequences voor de surrogaatsleutels van de eigen tabellen.
-- De GTFS-tabellen hebben al een eigen code als sleutel en hebben dus
-- geen sequence nodig.
--
-- Elke sequence wordt als DEFAULT aan de id-kolom gekoppeld, zodat een
-- INSERT zonder id automatisch het volgende nummer krijgt.
--
-- CACHE 20: Oracle houdt 20 nummers klaar in het geheugen (sneller).
-- Gevolg: na een herstart van de database kunnen er gaten in de
-- nummering zitten. Dat is geen probleem: een surrogaatsleutel moet
-- uniek zijn, niet aaneensluitend.
-- =====================================================================

-- Bestaande sequences verwijderen, zodat dit script herhaalbaar is
BEGIN
  FOR s IN (SELECT sequence_name FROM user_sequences
            WHERE sequence_name IN ('SEQ_GEBRUIKER', 'SEQ_STORING', 'SEQ_STORING_LOG')) LOOP
    EXECUTE IMMEDIATE 'DROP SEQUENCE ' || s.sequence_name;
  END LOOP;
END;
/

CREATE SEQUENCE seq_gebruiker   START WITH 1 INCREMENT BY 1 NOCYCLE CACHE 20;
CREATE SEQUENCE seq_storing     START WITH 1 INCREMENT BY 1 NOCYCLE CACHE 20;
CREATE SEQUENCE seq_storing_log START WITH 1 INCREMENT BY 1 NOCYCLE CACHE 20;

-- Sequences koppelen als standaardwaarde van de id-kolommen
ALTER TABLE gebruiker   MODIFY (gebruiker_id DEFAULT seq_gebruiker.NEXTVAL);
ALTER TABLE storing     MODIFY (storing_id   DEFAULT seq_storing.NEXTVAL);
ALTER TABLE storing_log MODIFY (log_id       DEFAULT seq_storing_log.NEXTVAL);
