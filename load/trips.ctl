-- SQL*Loader control file voor data/raw/trips.txt -> stg_trips
-- SKIP=1 slaat de headerregel over; TRUNCATE leegt de tabel eerst,
-- zodat opnieuw laden geen dubbele rijen geeft.
OPTIONS (SKIP=1)
LOAD DATA
CHARACTERSET UTF8
INFILE 'data\raw\trips.txt'
TRUNCATE
INTO TABLE stg_trips
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
TRAILING NULLCOLS
(
  route_id, service_id, trip_id, trip_headsign, direction_id,
  block_id, shape_id
)
