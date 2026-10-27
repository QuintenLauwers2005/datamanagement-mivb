-- SQL*Loader control file voor data/raw/routes.txt -> stg_routes
-- SKIP=1 slaat de headerregel over; TRUNCATE leegt de tabel eerst,
-- zodat opnieuw laden geen dubbele rijen geeft.
OPTIONS (SKIP=1)
LOAD DATA
CHARACTERSET UTF8
INFILE 'data\raw\routes.txt'
TRUNCATE
INTO TABLE stg_routes
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
TRAILING NULLCOLS
(
  route_id, agency_id, route_short_name, route_long_name, route_desc,
  route_type, route_url, route_color, route_text_color
)
