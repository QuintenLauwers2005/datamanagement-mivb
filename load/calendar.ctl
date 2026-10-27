-- SQL*Loader control file voor data/raw/calendar.txt -> stg_calendar
-- SKIP=1 slaat de headerregel over; TRUNCATE leegt de tabel eerst,
-- zodat opnieuw laden geen dubbele rijen geeft.
OPTIONS (SKIP=1)
LOAD DATA
CHARACTERSET UTF8
INFILE 'data\raw\calendar.txt'
TRUNCATE
INTO TABLE stg_calendar
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
TRAILING NULLCOLS
(
  service_id, monday, tuesday, wednesday, thursday, friday,
  saturday, sunday, start_date, end_date
)
