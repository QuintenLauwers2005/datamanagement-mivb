-- =====================================================================
-- 03_controle_transformatie.sql
-- Uit te voeren als MIVB na 04_transformatie.sql, als script (F5)
-- =====================================================================

-- 1. Aantal rijen: staging naast model (moeten gelijk zijn)
SELECT 'routes -> lijn'                 AS tabel, (SELECT COUNT(*) FROM stg_routes)         AS staging, (SELECT COUNT(*) FROM lijn)                        AS model FROM dual UNION ALL
SELECT 'stops -> halte',                          (SELECT COUNT(*) FROM stg_stops),                    (SELECT COUNT(*) FROM halte)                              FROM dual UNION ALL
SELECT 'calendar -> dienstregeling',              (SELECT COUNT(*) FROM stg_calendar),                 (SELECT COUNT(*) FROM dienstregeling)                     FROM dual UNION ALL
SELECT 'calendar_dates -> uitzondering',          (SELECT COUNT(*) FROM stg_calendar_dates),           (SELECT COUNT(*) FROM dienstregeling_uitzondering)        FROM dual UNION ALL
SELECT 'trips -> rit',                            (SELECT COUNT(*) FROM stg_trips),                    (SELECT COUNT(*) FROM rit)                                FROM dual UNION ALL
SELECT 'stop_times -> doortocht',                 (SELECT COUNT(*) FROM stg_stop_times),               (SELECT COUNT(*) FROM doortocht)                          FROM dual;

-- 2. Vervoerstypes en aantal lijnen per type
SELECT v.type_id, v.naam, COUNT(l.lijn_id) AS aantal_lijnen
FROM   vervoerstype v
LEFT JOIN lijn l ON l.type_id = v.type_id
GROUP  BY v.type_id, v.naam
ORDER  BY v.type_id;

-- 3. Vertalingen: hoeveel haltes en lijnen hebben geen Nederlandse naam?
SELECT (SELECT COUNT(*) FROM halte WHERE naam_nl IS NULL) AS haltes_zonder_nl,
       (SELECT COUNT(*) FROM lijn  WHERE lange_naam_nl IS NULL) AS lijnen_zonder_nl
FROM dual;

-- Voorbeelden waar de Franse en Nederlandse naam verschillen
SELECT halte_id, naam_fr, naam_nl
FROM   halte
WHERE  naam_nl <> naam_fr
FETCH FIRST 10 ROWS ONLY;

-- 4. Stations en hun perrons
SELECT (SELECT COUNT(*) FROM halte WHERE locatietype = 1)        AS stations,
       (SELECT COUNT(*) FROM halte WHERE station_id IS NOT NULL) AS perrons_met_station
FROM dual;

-- 5. Tijdsomzetting nakijken: originele tekst naast seconden
--    (een rit na middernacht: vertrek_sec moet > 86400 zijn)
SELECT st.departure_time,
       d.vertrek_sec,
       TRUNC(d.vertrek_sec / 3600)          AS uur,
       TRUNC(MOD(d.vertrek_sec, 3600) / 60) AS minuut
FROM   doortocht d
JOIN   stg_stop_times st
       ON st.trip_id = d.rit_id AND TO_NUMBER(st.stop_sequence) = d.volgnummer
WHERE  d.vertrek_sec = (SELECT MAX(vertrek_sec) FROM doortocht)
FETCH FIRST 1 ROWS ONLY;

-- 6. Statistieken: weet de optimizer hoeveel rijen er zijn?
SELECT table_name, num_rows, last_analyzed
FROM   user_tables
WHERE  table_name NOT LIKE 'STG\_%' ESCAPE '\'
ORDER  BY table_name;
