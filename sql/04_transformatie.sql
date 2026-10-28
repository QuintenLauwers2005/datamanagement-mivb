-- =====================================================================
-- 04_transformatie.sql
-- Uit te voeren als MIVB, NA 01-03 en load\laden.ps1, als script (F5)
--
-- Zet de ruwe data uit de staging-tabellen (alles VARCHAR2) om naar het
-- eigen model, met de juiste datatypes:
--   * tijden 'HH:MM:SS' -> seconden sinds middernacht (NUMBER)
--   * datums 'YYYYMMDD' -> DATE
--   * vlaggen '0'/'1'   -> NUMBER(1)
--   * vertalingen uit stg_translations -> naam_fr / naam_nl
--
-- Het script is herhaalbaar: het maakt de GTFS-tabellen eerst leeg.
-- Let op: favorieten en storingen verwijzen naar haltes en lijnen en
-- worden daarom ook gewist.
-- Duurt ongeveer een minuut (vooral doortocht: 1,5 miljoen rijen).
-- =====================================================================

-- De coordinaten gebruiken een punt als decimaalteken (50.838006).
-- Met Belgische instellingen verwacht Oracle een komma, dus leggen we
-- het decimaalteken voor deze sessie vast.
ALTER SESSION SET NLS_NUMERIC_CHARACTERS = '.,';

-- ---------------------------------------------------------------------
-- 0. Bestaande data verwijderen (kinderen voor ouders)
-- ---------------------------------------------------------------------
-- doortocht wordt door geen enkele tabel gerefereerd: TRUNCATE kan
-- (veel sneller dan DELETE, maar kan niet ongedaan gemaakt worden).
TRUNCATE TABLE doortocht;
DELETE FROM favoriete_halte;
DELETE FROM storing;
DELETE FROM rit;
DELETE FROM dienstregeling_uitzondering;
DELETE FROM dienstregeling;
UPDATE halte SET station_id = NULL;   -- eerst de zelfverwijzing loskoppelen
DELETE FROM halte;
DELETE FROM lijn;
DELETE FROM vervoerstype;
COMMIT;

-- ---------------------------------------------------------------------
-- 1. vervoerstype: afgeleid uit de route_types die echt voorkomen
-- ---------------------------------------------------------------------
INSERT INTO vervoerstype (type_id, naam)
SELECT DISTINCT
       TO_NUMBER(route_type),
       CASE TO_NUMBER(route_type)
         WHEN 0 THEN 'Tram'
         WHEN 1 THEN 'Metro'
         WHEN 3 THEN 'Bus'
         ELSE 'Type ' || route_type
       END
FROM   stg_routes;

-- ---------------------------------------------------------------------
-- 2. lijn: met Franse en Nederlandse naam uit stg_translations
--    Vertalingen hangen aan de tekst zelf (field_value), niet aan een id.
-- ---------------------------------------------------------------------
INSERT INTO lijn (lijn_id, korte_naam, lange_naam_fr, lange_naam_nl,
                  type_id, kleur, tekstkleur)
SELECT r.route_id,
       r.route_short_name,
       COALESCE(fr.translation, r.route_long_name),
       nl.translation,                       -- NULL als er geen vertaling is
       TO_NUMBER(r.route_type),
       r.route_color,
       r.route_text_color
FROM   stg_routes r
LEFT JOIN (SELECT field_value, MAX(translation) AS translation
           FROM   stg_translations
           WHERE  table_name = 'routes' AND field_name = 'route_long_name' AND language = 'fr'
           GROUP  BY field_value) fr ON fr.field_value = r.route_long_name
LEFT JOIN (SELECT field_value, MAX(translation) AS translation
           FROM   stg_translations
           WHERE  table_name = 'routes' AND field_name = 'route_long_name' AND language = 'nl'
           GROUP  BY field_value) nl ON nl.field_value = r.route_long_name;

-- ---------------------------------------------------------------------
-- 3. dienstregeling en uitzonderingen
-- ---------------------------------------------------------------------
INSERT INTO dienstregeling (service_id, maandag, dinsdag, woensdag, donderdag,
                            vrijdag, zaterdag, zondag, startdatum, einddatum)
SELECT service_id,
       TO_NUMBER(monday), TO_NUMBER(tuesday), TO_NUMBER(wednesday),
       TO_NUMBER(thursday), TO_NUMBER(friday), TO_NUMBER(saturday),
       TO_NUMBER(sunday),
       TO_DATE(start_date, 'YYYYMMDD'),
       TO_DATE(end_date,   'YYYYMMDD')
FROM   stg_calendar;

INSERT INTO dienstregeling_uitzondering (service_id, datum, uitzonderingstype)
SELECT service_id,
       TO_DATE(datum, 'YYYYMMDD'),
       TO_NUMBER(exception_type)
FROM   stg_calendar_dates;

-- ---------------------------------------------------------------------
-- 4. halte: in twee stappen vanwege de zelfverwijzing
--    Stap a: alle haltes zonder station_id, zodat elke halte al bestaat.
--    Stap b: station_id invullen. Zo maakt de volgorde van de rijen niet
--    uit voor de foreign key fk_halte_station.
-- ---------------------------------------------------------------------
INSERT INTO halte (halte_id, naam_fr, naam_nl, breedtegraad, lengtegraad, locatietype)
SELECT s.stop_id,
       COALESCE(fr.translation, s.stop_name),
       nl.translation,                       -- NULL als er geen vertaling is
       TO_NUMBER(s.stop_lat),
       TO_NUMBER(s.stop_lon),
       NVL(TO_NUMBER(s.location_type), 0)    -- leeg = 0 volgens GTFS
FROM   stg_stops s
LEFT JOIN (SELECT field_value, MAX(translation) AS translation
           FROM   stg_translations
           WHERE  table_name = 'stops' AND field_name = 'stop_name' AND language = 'fr'
           GROUP  BY field_value) fr ON fr.field_value = s.stop_name
LEFT JOIN (SELECT field_value, MAX(translation) AS translation
           FROM   stg_translations
           WHERE  table_name = 'stops' AND field_name = 'stop_name' AND language = 'nl'
           GROUP  BY field_value) nl ON nl.field_value = s.stop_name;

UPDATE halte h
SET    h.station_id = (SELECT s.parent_station
                       FROM   stg_stops s
                       WHERE  s.stop_id = h.halte_id)
WHERE  EXISTS (SELECT 1 FROM stg_stops s
               WHERE  s.stop_id = h.halte_id AND s.parent_station IS NOT NULL);

-- ---------------------------------------------------------------------
-- 5. rit
-- ---------------------------------------------------------------------
INSERT INTO rit (rit_id, lijn_id, service_id, bestemming, richting)
SELECT trip_id, route_id, service_id, trip_headsign, TO_NUMBER(direction_id)
FROM   stg_trips;

-- ---------------------------------------------------------------------
-- 6. doortocht: 'HH:MM:SS' omzetten naar seconden
--    LPAD maakt van '4:26:00' eerst '04:26:00', zodat de posities kloppen.
--    Voorbeeld: '27:58:00' -> 27*3600 + 58*60 + 0 = 100680
-- ---------------------------------------------------------------------
INSERT INTO doortocht (rit_id, volgnummer, halte_id, aankomst_sec, vertrek_sec)
SELECT trip_id,
       TO_NUMBER(stop_sequence),
       stop_id,
       TO_NUMBER(SUBSTR(LPAD(arrival_time, 8, '0'), 1, 2)) * 3600
     + TO_NUMBER(SUBSTR(LPAD(arrival_time, 8, '0'), 4, 2)) * 60
     + TO_NUMBER(SUBSTR(LPAD(arrival_time, 8, '0'), 7, 2)),
       TO_NUMBER(SUBSTR(LPAD(departure_time, 8, '0'), 1, 2)) * 3600
     + TO_NUMBER(SUBSTR(LPAD(departure_time, 8, '0'), 4, 2)) * 60
     + TO_NUMBER(SUBSTR(LPAD(departure_time, 8, '0'), 7, 2))
FROM   stg_stop_times;

COMMIT;

-- ---------------------------------------------------------------------
-- 7. Statistieken verzamelen
--    De query optimizer kiest een uitvoeringsplan op basis van
--    statistieken (aantal rijen, verdeling van waarden). Zonder actuele
--    statistieken kan hij verkeerde keuzes maken, en dan zijn de
--    EXPLAIN PLAN-metingen in de index-tests niet betrouwbaar.
-- ---------------------------------------------------------------------
BEGIN
  DBMS_STATS.GATHER_SCHEMA_STATS(ownname => USER);
END;
/
