-- =====================================================================
-- 02_controle_model.sql
-- Uit te voeren als MIVB na 02 en 03, als script (F5)
-- Controleert de structuur via de data dictionary.
-- =====================================================================

-- 1. Welke tabellen bestaan er (zonder staging)?
SELECT table_name
FROM   user_tables
WHERE  table_name NOT LIKE 'STG\_%' ESCAPE '\'
ORDER  BY table_name;

-- 2. Aantal constraints per tabel en type
--    P = primary key, R = foreign key (referential), U = unique, C = check / not null
SELECT table_name, constraint_type, COUNT(*) AS aantal
FROM   user_constraints
WHERE  table_name NOT LIKE 'STG\_%' ESCAPE '\'
GROUP  BY table_name, constraint_type
ORDER  BY table_name, constraint_type;

-- 3. Alle foreign keys: welke tabel verwijst naar welke
SELECT c.table_name, c.constraint_name, p.table_name AS verwijst_naar, c.delete_rule
FROM   user_constraints c
JOIN   user_constraints p ON p.constraint_name = c.r_constraint_name
WHERE  c.constraint_type = 'R'
ORDER  BY c.table_name;

-- 4. Indexen die Oracle automatisch maakte (voor PK en UNIQUE)
SELECT table_name, index_name, uniqueness
FROM   user_indexes
WHERE  table_name NOT LIKE 'STG\_%' ESCAPE '\'
ORDER  BY table_name;

-- 5. Sequences en hun gekoppelde kolommen
SELECT sequence_name, last_number, cache_size FROM user_sequences ORDER BY sequence_name;

SELECT table_name, column_name, data_default
FROM   user_tab_columns
WHERE  column_name IN ('GEBRUIKER_ID', 'STORING_ID', 'LOG_ID')
AND    table_name IN ('GEBRUIKER', 'STORING', 'STORING_LOG');

-- 6. Test: een gebruiker toevoegen zonder id (de sequence vult het in)
INSERT INTO gebruiker (email, naam) VALUES ('test@voorbeeld.be', 'Testgebruiker');
SELECT gebruiker_id, email, aangemaakt_op FROM gebruiker;
ROLLBACK;  -- testrij niet bewaren

-- 7. Test: een storing zonder lijn en zonder halte moet GEWEIGERD worden
--    Verwachte fout: ORA-02290: check constraint (MIVB.CK_STORING_DOEL) violated
INSERT INTO storing (omschrijving) VALUES ('Deze insert hoort te falen');
ROLLBACK;
