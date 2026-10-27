-- =====================================================================
-- 01_controle_staging.sql
-- Uit te voeren als MIVB na load\laden.ps1, als script (F5)
-- De resultaten bepalen een paar keuzes in het datamodel.
-- =====================================================================

-- 1. Aantal rijen per tabel
--    (stg_stop_times zou 1.559.649 moeten zijn: 1.559.650 regels min de header)
SELECT 'stg_routes'         AS tabel, COUNT(*) AS aantal FROM stg_routes         UNION ALL
SELECT 'stg_stops',                   COUNT(*)           FROM stg_stops          UNION ALL
SELECT 'stg_calendar',                COUNT(*)           FROM stg_calendar       UNION ALL
SELECT 'stg_calendar_dates',          COUNT(*)           FROM stg_calendar_dates UNION ALL
SELECT 'stg_trips',                   COUNT(*)           FROM stg_trips          UNION ALL
SELECT 'stg_translations',            COUNT(*)           FROM stg_translations   UNION ALL
SELECT 'stg_stop_times',              COUNT(*)           FROM stg_stop_times;

-- 2. Maximale lengte van de codes (bepaalt de VARCHAR2-lengtes in het datamodel)
SELECT MAX(LENGTH(route_id))   AS max_route_id,
       MAX(LENGTH(service_id)) AS max_service_id,
       MAX(LENGTH(trip_id))    AS max_trip_id
FROM   stg_trips;

SELECT MAX(LENGTH(stop_id))    AS max_stop_id,
       MAX(LENGTH(stop_name))  AS max_stop_name
FROM   stg_stops;

-- 3. Hoogste volgnummer in een rit (past NUMBER(3)?)
SELECT MAX(TO_NUMBER(stop_sequence)) AS max_volgnummer FROM stg_stop_times;

-- 4. Doortochten na middernacht (tijd >= 24:00:00)
--    LPAD vangt tijden zonder voorloopnul op (bv. 4:26:00)
SELECT COUNT(*)            AS aantal_na_middernacht,
       MAX(departure_time) AS laatste_vertrek
FROM   stg_stop_times
WHERE  LPAD(departure_time, 8, '0') >= '24:00:00';

-- 5. service_id's in calendar_dates die NIET in calendar staan
SELECT COUNT(DISTINCT cd.service_id) AS enkel_in_calendar_dates
FROM   stg_calendar_dates cd
WHERE  NOT EXISTS (SELECT 1 FROM stg_calendar c WHERE c.service_id = cd.service_id);

-- 6. parent_station's die niet als stop_id bestaan
SELECT COUNT(*) AS ontbrekende_stations
FROM   stg_stops s
WHERE  s.parent_station IS NOT NULL
AND    NOT EXISTS (SELECT 1 FROM stg_stops p WHERE p.stop_id = s.parent_station);

-- 7. Verwijzingen vanuit stop_times die nergens naar wijzen
SELECT
  (SELECT COUNT(*) FROM stg_stop_times st
   WHERE NOT EXISTS (SELECT 1 FROM stg_trips t WHERE t.trip_id = st.trip_id)) AS trips_ontbreken,
  (SELECT COUNT(*) FROM stg_stop_times st
   WHERE NOT EXISTS (SELECT 1 FROM stg_stops s WHERE s.stop_id = st.stop_id)) AS stops_ontbreken
FROM dual;

-- 8. Haltes met een voorloopnul (bevestigt de keuze voor VARCHAR2)
SELECT COUNT(*) AS haltes_met_voorloopnul FROM stg_stops WHERE stop_id LIKE '0%';

-- 9. Welke vertalingen zitten er in translations?
SELECT table_name, field_name, language, COUNT(*) AS aantal
FROM   stg_translations
GROUP  BY table_name, field_name, language
ORDER  BY table_name, field_name, language;
