-- =====================================================================
-- 02_model_tabellen.sql
-- Uit te voeren als MIVB (connectie "MIVB project"), als script (F5)
--
-- Het eigen datamodel (zie docs/datamodel.md).
-- * Primaire sleutels: de GTFS-codes zelf (natuurlijke sleutels), behalve
--   bij de eigen tabellen gebruiker, storing en storing_log (surrogaatsleutel
--   via sequence, zie 03_sequences.sql).
-- * Alle constraints krijgen een naam (pk_, fk_, uk_, ck_), zodat ze
--   herkenbaar zijn in foutmeldingen en in de data dictionary
--   (USER_CONSTRAINTS).
-- * Oracle maakt automatisch een index voor elke PK en UNIQUE-constraint,
--   maar NIET voor foreign keys. Die indexen komen in 05_indexen.sql.
-- =====================================================================

-- Bestaande modeltabellen verwijderen, zodat dit script herhaalbaar is
BEGIN
  FOR t IN (SELECT table_name FROM user_tables
            WHERE table_name IN ('STORING_LOG', 'STORING', 'FAVORIETE_HALTE',
                                 'GEBRUIKER', 'DOORTOCHT', 'RIT', 'HALTE',
                                 'DIENSTREGELING_UITZONDERING', 'DIENSTREGELING',
                                 'LIJN', 'VERVOERSTYPE')) LOOP
    EXECUTE IMMEDIATE 'DROP TABLE ' || t.table_name || ' CASCADE CONSTRAINTS PURGE';
  END LOOP;
END;
/

-- ---------------------------------------------------------------------
-- Deel 1: tabellen gevuld vanuit GTFS
-- ---------------------------------------------------------------------

CREATE TABLE vervoerstype (
  type_id  NUMBER(2)    CONSTRAINT pk_vervoerstype PRIMARY KEY,
  naam     VARCHAR2(20) CONSTRAINT nn_vervoerstype_naam NOT NULL,
  CONSTRAINT uk_vervoerstype_naam UNIQUE (naam)
);

CREATE TABLE lijn (
  lijn_id        VARCHAR2(10)  CONSTRAINT pk_lijn PRIMARY KEY,
  korte_naam     VARCHAR2(10)  CONSTRAINT nn_lijn_korte_naam NOT NULL,
  lange_naam_fr  VARCHAR2(100),
  lange_naam_nl  VARCHAR2(100),
  type_id        NUMBER(2)     CONSTRAINT nn_lijn_type NOT NULL,
  kleur          CHAR(6),
  tekstkleur     CHAR(6),
  CONSTRAINT fk_lijn_vervoerstype FOREIGN KEY (type_id) REFERENCES vervoerstype (type_id),
  CONSTRAINT ck_lijn_kleur        CHECK (REGEXP_LIKE(kleur, '^[0-9A-Fa-f]{6}$')),
  CONSTRAINT ck_lijn_tekstkleur   CHECK (REGEXP_LIKE(tekstkleur, '^[0-9A-Fa-f]{6}$'))
);

CREATE TABLE dienstregeling (
  service_id  VARCHAR2(10) CONSTRAINT pk_dienstregeling PRIMARY KEY,
  maandag     NUMBER(1) NOT NULL CONSTRAINT ck_dr_maandag   CHECK (maandag   IN (0, 1)),
  dinsdag     NUMBER(1) NOT NULL CONSTRAINT ck_dr_dinsdag   CHECK (dinsdag   IN (0, 1)),
  woensdag    NUMBER(1) NOT NULL CONSTRAINT ck_dr_woensdag  CHECK (woensdag  IN (0, 1)),
  donderdag   NUMBER(1) NOT NULL CONSTRAINT ck_dr_donderdag CHECK (donderdag IN (0, 1)),
  vrijdag     NUMBER(1) NOT NULL CONSTRAINT ck_dr_vrijdag   CHECK (vrijdag   IN (0, 1)),
  zaterdag    NUMBER(1) NOT NULL CONSTRAINT ck_dr_zaterdag  CHECK (zaterdag  IN (0, 1)),
  zondag      NUMBER(1) NOT NULL CONSTRAINT ck_dr_zondag    CHECK (zondag    IN (0, 1)),
  startdatum  DATE      NOT NULL,
  einddatum   DATE      NOT NULL,
  CONSTRAINT ck_dr_periode CHECK (einddatum >= startdatum)
);

-- Identificerende relatie: een uitzondering bestaat enkel binnen een
-- dienstregeling, vandaar de samengestelde PK en ON DELETE CASCADE.
CREATE TABLE dienstregeling_uitzondering (
  service_id         VARCHAR2(10),
  datum              DATE,
  uitzonderingstype  NUMBER(1) NOT NULL,
  CONSTRAINT pk_dr_uitzondering PRIMARY KEY (service_id, datum),
  CONSTRAINT fk_dru_dienstregeling FOREIGN KEY (service_id)
    REFERENCES dienstregeling (service_id) ON DELETE CASCADE,
  CONSTRAINT ck_dru_type CHECK (uitzonderingstype IN (1, 2))  -- 1 = extra dag, 2 = geschrapt
);

CREATE TABLE halte (
  halte_id      VARCHAR2(10)  CONSTRAINT pk_halte PRIMARY KEY,  -- VARCHAR2: voorloopnullen (0089)
  naam_fr       VARCHAR2(100) CONSTRAINT nn_halte_naam_fr NOT NULL,
  naam_nl       VARCHAR2(100),
  breedtegraad  NUMBER(9,6)   CONSTRAINT nn_halte_lat NOT NULL,
  lengtegraad   NUMBER(9,6)   CONSTRAINT nn_halte_lon NOT NULL,
  locatietype   NUMBER(1)     DEFAULT 0 NOT NULL,
  station_id    VARCHAR2(10),
  CONSTRAINT fk_halte_station FOREIGN KEY (station_id) REFERENCES halte (halte_id),  -- zelfverwijzing
  CONSTRAINT ck_halte_type    CHECK (locatietype IN (0, 1, 2, 3, 4)),  -- GTFS: 0 halte/perron, 1 station, 2 ingang, 3 knooppunt, 4 instapzone
  CONSTRAINT ck_halte_lat     CHECK (breedtegraad BETWEEN -90 AND 90),
  CONSTRAINT ck_halte_lon     CHECK (lengtegraad BETWEEN -180 AND 180)
);

CREATE TABLE rit (
  rit_id      VARCHAR2(20)  CONSTRAINT pk_rit PRIMARY KEY,
  lijn_id     VARCHAR2(10)  CONSTRAINT nn_rit_lijn NOT NULL,
  service_id  VARCHAR2(10)  CONSTRAINT nn_rit_service NOT NULL,
  bestemming  VARCHAR2(100),
  richting    NUMBER(1)     CONSTRAINT nn_rit_richting NOT NULL,
  CONSTRAINT fk_rit_lijn           FOREIGN KEY (lijn_id)    REFERENCES lijn (lijn_id),
  CONSTRAINT fk_rit_dienstregeling FOREIGN KEY (service_id) REFERENCES dienstregeling (service_id),
  CONSTRAINT ck_rit_richting       CHECK (richting IN (0, 1))
);

-- De grote tabel (±1,56 miljoen rijen).
-- Tijden in seconden sinds middernacht: GTFS-tijden gaan tot 27:58:00
-- (= 100.680 s), wat een DATE niet kan voorstellen.
CREATE TABLE doortocht (
  rit_id        VARCHAR2(20),
  volgnummer    NUMBER(3),
  halte_id      VARCHAR2(10) CONSTRAINT nn_doortocht_halte NOT NULL,
  aankomst_sec  NUMBER(6)    CONSTRAINT nn_doortocht_aankomst NOT NULL,
  vertrek_sec   NUMBER(6)    CONSTRAINT nn_doortocht_vertrek NOT NULL,
  CONSTRAINT pk_doortocht PRIMARY KEY (rit_id, volgnummer),
  CONSTRAINT fk_doortocht_rit   FOREIGN KEY (rit_id)   REFERENCES rit (rit_id) ON DELETE CASCADE,
  CONSTRAINT fk_doortocht_halte FOREIGN KEY (halte_id) REFERENCES halte (halte_id),
  CONSTRAINT ck_doortocht_tijd  CHECK (aankomst_sec >= 0 AND vertrek_sec >= aankomst_sec)
);

-- ---------------------------------------------------------------------
-- Deel 2: eigen tabellen van de reisinfo-app
-- De id's worden ingevuld door een sequence (zie 03_sequences.sql).
-- ---------------------------------------------------------------------

CREATE TABLE gebruiker (
  gebruiker_id   NUMBER(10)    CONSTRAINT pk_gebruiker PRIMARY KEY,
  email          VARCHAR2(255) CONSTRAINT nn_gebruiker_email NOT NULL,
  naam           VARCHAR2(100),
  aangemaakt_op  DATE          DEFAULT SYSDATE NOT NULL,
  CONSTRAINT uk_gebruiker_email UNIQUE (email),
  CONSTRAINT ck_gebruiker_email CHECK (email LIKE '_%@_%._%')
);

-- Koppeltabel voor de veel-op-veel-relatie gebruiker <-> halte
CREATE TABLE favoriete_halte (
  gebruiker_id   NUMBER(10),
  halte_id       VARCHAR2(10),
  toegevoegd_op  DATE DEFAULT SYSDATE NOT NULL,
  CONSTRAINT pk_favoriete_halte PRIMARY KEY (gebruiker_id, halte_id),
  CONSTRAINT fk_fav_gebruiker FOREIGN KEY (gebruiker_id)
    REFERENCES gebruiker (gebruiker_id) ON DELETE CASCADE,
  CONSTRAINT fk_fav_halte FOREIGN KEY (halte_id) REFERENCES halte (halte_id)
);

CREATE TABLE storing (
  storing_id    NUMBER(10)    CONSTRAINT pk_storing PRIMARY KEY,
  lijn_id       VARCHAR2(10),
  halte_id      VARCHAR2(10),
  omschrijving  VARCHAR2(500) CONSTRAINT nn_storing_omschrijving NOT NULL,
  start_tijd    TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL,
  eind_tijd     TIMESTAMP,
  status        VARCHAR2(10)  DEFAULT 'ACTIEF' NOT NULL,
  CONSTRAINT fk_storing_lijn  FOREIGN KEY (lijn_id)  REFERENCES lijn (lijn_id),
  CONSTRAINT fk_storing_halte FOREIGN KEY (halte_id) REFERENCES halte (halte_id),
  -- een storing gaat over minstens een lijn of een halte
  CONSTRAINT ck_storing_doel   CHECK (lijn_id IS NOT NULL OR halte_id IS NOT NULL),
  CONSTRAINT ck_storing_status CHECK (status IN ('ACTIEF', 'OPGELOST')),
  -- een opgeloste storing heeft een eindtijd, een actieve niet
  CONSTRAINT ck_storing_eind CHECK (
       (status = 'ACTIEF'   AND eind_tijd IS NULL)
    OR (status = 'OPGELOST' AND eind_tijd IS NOT NULL AND eind_tijd >= start_tijd))
);

-- Auditlog, gevuld door een trigger (07_triggers.sql).
-- Bewust GEEN foreign key naar storing: de log moet blijven bestaan,
-- ook als de storing zelf verwijderd wordt.
CREATE TABLE storing_log (
  log_id          NUMBER(10)    CONSTRAINT pk_storing_log PRIMARY KEY,
  storing_id      NUMBER(10)    CONSTRAINT nn_log_storing NOT NULL,
  actie           VARCHAR2(10)  CONSTRAINT nn_log_actie NOT NULL,
  oude_status     VARCHAR2(10),
  nieuwe_status   VARCHAR2(10),
  gewijzigd_door  VARCHAR2(128) DEFAULT USER NOT NULL,
  gewijzigd_op    TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT ck_log_actie CHECK (actie IN ('INSERT', 'UPDATE', 'DELETE'))
);

-- ---------------------------------------------------------------------
-- Commentaar in de data dictionary (zichtbaar via USER_TAB_COMMENTS
-- en USER_COL_COMMENTS)
-- ---------------------------------------------------------------------
COMMENT ON TABLE  lijn            IS 'Tram-, metro- en buslijnen van de MIVB (GTFS routes)';
COMMENT ON TABLE  halte           IS 'Haltes, perrons en stations (GTFS stops + vertalingen)';
COMMENT ON TABLE  rit             IS 'Een individuele rit van een lijn (GTFS trips)';
COMMENT ON TABLE  doortocht       IS 'Tijdstip waarop een rit een halte passeert (GTFS stop_times)';
COMMENT ON TABLE  dienstregeling  IS 'Op welke weekdagen en in welke periode ritten rijden (GTFS calendar)';
COMMENT ON TABLE  dienstregeling_uitzondering IS 'Extra of geschrapte dagen (GTFS calendar_dates)';
COMMENT ON TABLE  storing         IS 'Storingen ingevoerd door beheerders';
COMMENT ON TABLE  storing_log     IS 'Auditlog van storingen, gevuld door een trigger';
COMMENT ON COLUMN doortocht.vertrek_sec IS 'Seconden sinds middernacht van de dienstdag; kan groter zijn dan 86400';
COMMENT ON COLUMN halte.station_id      IS 'Verwijst naar het station (locatietype 1) waartoe dit perron behoort';
