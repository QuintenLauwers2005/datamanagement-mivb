-- SQL*Loader control file voor data/raw/translations.txt -> stg_translations
-- SKIP=1 slaat de headerregel over; TRUNCATE leegt de tabel eerst,
-- zodat opnieuw laden geen dubbele rijen geeft.
-- CHAR(500): SQL*Loader leest velden standaard als maximaal 255 tekens.
OPTIONS (SKIP=1)
LOAD DATA
CHARACTERSET UTF8
INFILE 'data\raw\translations.txt'
TRUNCATE
INTO TABLE stg_translations
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
TRAILING NULLCOLS
(
  table_name, field_name, language,
  translation CHAR(500), field_value CHAR(500)
)
