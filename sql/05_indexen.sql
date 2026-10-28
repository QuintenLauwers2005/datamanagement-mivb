-- =====================================================================
-- 05_indexen.sql
-- Uit te voeren als MIVB, NA 04_transformatie.sql, als script (F5)
--
-- Oracle maakt automatisch een index voor elke PRIMARY KEY en UNIQUE-
-- constraint, maar NIET voor foreign keys. Dit script voegt de indexen
-- toe die de use case nodig heeft.
--
-- Een index is niet gratis: hij neemt opslagruimte in en elke INSERT,
-- UPDATE of DELETE moet ook de index bijwerken. Daarom krijgt enkel een
-- kolom een index als er effectief op gezocht of gejoind wordt.
--
-- De meting die het effect aantoont: tests/04_performantie_indexen.sql
-- =====================================================================

-- Bestaande indexen verwijderen, zodat dit script herhaalbaar is
BEGIN
  FOR i IN (SELECT index_name FROM user_indexes
            WHERE index_name IN ('IDX_DOORTOCHT_HALTE', 'IDX_DOORTOCHT_HALTE_VERTREK',
                                 'IDX_RIT_LIJN', 'IDX_RIT_SERVICE', 'IDX_HALTE_STATION',
                                 'IDX_FAV_HALTE', 'IDX_STORING_LIJN', 'IDX_STORING_HALTE')) LOOP
    EXECUTE IMMEDIATE 'DROP INDEX ' || i.index_name;
  END LOOP;
END;
/

-- ---------------------------------------------------------------------
-- 1. De belangrijkste index: volgende vertrekken aan een halte
--
-- Kernquery van de app:
--   WHERE halte_id = :halte AND vertrek_sec >= :nu ORDER BY vertrek_sec
--
-- Samengestelde index (halte_id, vertrek_sec):
-- * halte_id EERST: daarop wordt met = gezocht. Binnen één halte staan
--   de vertrektijden dan al gesorteerd in de index.
-- * vertrek_sec TWEEDE: Oracle kan meteen naar het juiste tijdstip
--   springen en de rijen in volgorde lezen, zonder aparte sortering.
-- * Omgekeerd (vertrek_sec, halte_id) zou veel minder goed werken: dan
--   staan alle haltes door elkaar binnen hetzelfde tijdstip.
-- * Omdat halte_id de eerste kolom is, dient deze index ook als index op
--   de foreign key fk_doortocht_halte. Een aparte index op enkel
--   halte_id is dus overbodig.
-- ---------------------------------------------------------------------
CREATE INDEX idx_doortocht_halte_vertrek ON doortocht (halte_id, vertrek_sec);

-- ---------------------------------------------------------------------
-- 2. Indexen op foreign keys
--
-- Waarom foreign keys een index nodig hebben:
-- * joins en zoekopdrachten op die kolom worden sneller;
-- * bij een DELETE of UPDATE van de ouderrij moet Oracle de kindtabel
--   controleren. Zonder index is dat een full table scan, en Oracle
--   vergrendelt dan de hele kindtabel tijdelijk (table lock).
--
-- Foreign keys die GEEN extra index nodig hebben, omdat ze al de eerste
-- kolom van een primaire sleutel zijn:
-- * doortocht.rit_id                   -> pk_doortocht (rit_id, volgnummer)
-- * dienstregeling_uitzondering.service_id -> pk_dr_uitzondering
-- * favoriete_halte.gebruiker_id       -> pk_favoriete_halte
-- * doortocht.halte_id                 -> idx_doortocht_halte_vertrek (hierboven)
-- ---------------------------------------------------------------------

-- Alle ritten van een lijn (rapporten per lijn, storing op een lijn)
CREATE INDEX idx_rit_lijn ON rit (lijn_id);

-- Welke ritten rijden volgens een dienstregeling (vertrekken van vandaag)
CREATE INDEX idx_rit_service ON rit (service_id);

-- Alle perrons en ingangen van een station
CREATE INDEX idx_halte_station ON halte (station_id);

-- Bij hoeveel gebruikers staat een halte als favoriet
-- (de PK begint met gebruiker_id en helpt hier dus niet)
CREATE INDEX idx_fav_halte ON favoriete_halte (halte_id);

-- Storingen op een lijn of halte opzoeken
CREATE INDEX idx_storing_lijn  ON storing (lijn_id);
CREATE INDEX idx_storing_halte ON storing (halte_id);

-- ---------------------------------------------------------------------
-- Bewust GEEN index:
-- * halte(naam_fr / naam_nl): slechts 2.752 rijen. Een full table scan
--   is daar al zeer snel; een index levert bijna niets op.
-- * doortocht(vertrek_sec) alleen: zonder halte_id ervoor zou een
--   zoekopdracht op tijd nog steeds duizenden rijen van alle haltes raken.
-- * kolommen met weinig verschillende waarden, zoals rit.richting (0/1)
--   of storing.status: een B-tree-index is daar weinig selectief.
-- ---------------------------------------------------------------------
