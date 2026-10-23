-- Uit te voeren als SYSTEM (connectie Lokaal MIVB)
-- Vervang <wachtwoord> door een eigen wachtwoord
CREATE USER mivb IDENTIFIED BY "<wachtwoord>" QUOTA UNLIMITED ON users;
GRANT CREATE SESSION, CREATE TABLE, CREATE VIEW, CREATE SEQUENCE,
      CREATE TRIGGER, CREATE PROCEDURE TO mivb;