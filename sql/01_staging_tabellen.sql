-- =====================================================================
-- 01_staging_tabellen.sql
-- Uit te voeren als MIVB (connectie "MIVB project"), als script (F5)
--
-- Staging-laag: een ruwe 1-op-1 kopie van de GTFS-bestanden.
-- * Alle kolommen zijn VARCHAR2, zodat de import nooit faalt op datatypes.
--   Het omzetten naar de juiste types gebeurt pas in 04_transformatie.sql.
-- * De kolommen staan in dezelfde volgorde als in de GTFS-bestanden,
--   want SQL*Loader koppelt de velden op volgorde.
-- * agency, feed_info en shapes worden niet ingeladen (zie ontwerpkeuzes.md).
-- =====================================================================

-- Bestaande staging-tabellen verwijderen, zodat dit script herhaalbaar is
BEGIN
  FOR t IN (SELECT table_name FROM user_tables
            WHERE table_name LIKE 'STG\_%' ESCAPE '\') LOOP
    EXECUTE IMMEDIATE 'DROP TABLE ' || t.table_name || ' PURGE';
  END LOOP;
END;
/

CREATE TABLE stg_routes (
  route_id          VARCHAR2(50),
  agency_id         VARCHAR2(50),
  route_short_name  VARCHAR2(50),
  route_long_name   VARCHAR2(255),
  route_desc        VARCHAR2(255),
  route_type        VARCHAR2(10),
  route_url         VARCHAR2(255),
  route_color       VARCHAR2(10),
  route_text_color  VARCHAR2(10)
);

CREATE TABLE stg_stops (
  stop_id         VARCHAR2(50),
  stop_code       VARCHAR2(50),
  stop_name       VARCHAR2(255),
  stop_desc       VARCHAR2(255),
  stop_lat        VARCHAR2(20),
  stop_lon        VARCHAR2(20),
  zone_id         VARCHAR2(50),
  stop_url        VARCHAR2(255),
  location_type   VARCHAR2(10),
  parent_station  VARCHAR2(50)
);

CREATE TABLE stg_calendar (
  service_id  VARCHAR2(50),
  monday      VARCHAR2(5),
  tuesday     VARCHAR2(5),
  wednesday   VARCHAR2(5),
  thursday    VARCHAR2(5),
  friday      VARCHAR2(5),
  saturday    VARCHAR2(5),
  sunday      VARCHAR2(5),
  start_date  VARCHAR2(10),
  end_date    VARCHAR2(10)
);

-- Let op: de GTFS-kolom heet "date", maar DATE is een gereserveerd woord
-- in Oracle. Daarom heet de kolom hier "datum".
CREATE TABLE stg_calendar_dates (
  service_id      VARCHAR2(50),
  datum           VARCHAR2(10),
  exception_type  VARCHAR2(5)
);

CREATE TABLE stg_trips (
  route_id       VARCHAR2(50),
  service_id     VARCHAR2(50),
  trip_id        VARCHAR2(50),
  trip_headsign  VARCHAR2(255),
  direction_id   VARCHAR2(5),
  block_id       VARCHAR2(50),
  shape_id       VARCHAR2(50)
);

CREATE TABLE stg_stop_times (
  trip_id         VARCHAR2(50),
  arrival_time    VARCHAR2(10),
  departure_time  VARCHAR2(10),
  stop_id         VARCHAR2(50),
  stop_sequence   VARCHAR2(10),
  pickup_type     VARCHAR2(5),
  drop_off_type   VARCHAR2(5),
  timepoint       VARCHAR2(5)
);

CREATE TABLE stg_translations (
  table_name   VARCHAR2(50),
  field_name   VARCHAR2(50),
  language     VARCHAR2(10),
  translation  VARCHAR2(500),
  field_value  VARCHAR2(500)
);
