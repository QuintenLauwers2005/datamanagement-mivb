-- SQL*Loader control file voor data/raw/stops.txt -> stg_stops
-- SKIP=1 slaat de headerregel over; TRUNCATE leegt de tabel eerst,
-- zodat opnieuw laden geen dubbele rijen geeft.
OPTIONS (SKIP=1)
LOAD DATA
CHARACTERSET UTF8
INFILE 'data\raw\stops.txt'
TRUNCATE
INTO TABLE stg_stops
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
TRAILING NULLCOLS
(
  stop_id, stop_code, stop_name, stop_desc, stop_lat, stop_lon,
  zone_id, stop_url, location_type, parent_station
)
