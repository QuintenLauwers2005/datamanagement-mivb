-- SQL*Loader control file voor data/raw/calendar_dates.txt -> stg_calendar_dates
-- SKIP=1 slaat de headerregel over; TRUNCATE leegt de tabel eerst,
-- zodat opnieuw laden geen dubbele rijen geeft.
OPTIONS (SKIP=1)
LOAD DATA
CHARACTERSET UTF8
INFILE 'data\raw\calendar_dates.txt'
TRUNCATE
INTO TABLE stg_calendar_dates
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
TRAILING NULLCOLS
(
  service_id, datum, exception_type
)
