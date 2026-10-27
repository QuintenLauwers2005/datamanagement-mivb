-- SQL*Loader control file voor data/raw/stop_times.txt -> stg_stop_times
-- SKIP=1 slaat de headerregel over; TRUNCATE leegt de tabel eerst,
-- zodat opnieuw laden geen dubbele rijen geeft.
-- DIRECT=TRUE: direct path load, schrijft rechtstreeks naar de datablokken
-- en is veel sneller voor de 1,5 miljoen rijen.
OPTIONS (SKIP=1, DIRECT=TRUE)
LOAD DATA
CHARACTERSET UTF8
INFILE 'data\raw\stop_times.txt'
TRUNCATE
INTO TABLE stg_stop_times
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
TRAILING NULLCOLS
(
  trip_id, arrival_time, departure_time, stop_id, stop_sequence,
  pickup_type, drop_off_type, timepoint
)
