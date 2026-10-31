-- =====================================================================
-- 06_views.sql
-- Uit te voeren als MIVB, NA 05_indexen.sql, als script (F5)
--
-- Views verbergen de complexiteit van het model voor de gebruikers:
-- de app en de analist hoeven niet te weten hoe dienstregelingen,
-- uitzonderingen en seconden sinds middernacht werken.
-- Ze zijn ook de basis voor de beveiliging (08_grants.sql): gebruikers
-- krijgen rechten op de views, niet op de tabellen.
--
-- CREATE OR REPLACE: het script is herhaalbaar zonder eerst te droppen.
-- WITH READ ONLY: via deze views kan niemand data wijzigen.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. v_actieve_dienst: welke dienstregelingen rijden op welke datum
--
-- GTFS beschrijft dit indirect:
--   * calendar: een periode + op welke weekdagen (maandag = 1, ...)
--   * calendar_dates: uitzonderingen (1 = extra dag, 2 = geschrapt)
-- Deze view rekent dat om naar een eenvoudige lijst (datum, service_id).
--
-- * De datums worden gegenereerd met CONNECT BY LEVEL: een rij per dag
--   tussen de vroegste startdatum en de laatste einddatum.
-- * Weekdag: datum - TRUNC(datum, 'IW') geeft 0 voor maandag tot 6 voor
--   zondag. 'IW' is de ISO-week en begint altijd op maandag, ongeacht de
--   taalinstellingen. TO_CHAR(datum, 'D') zou afhangen van NLS_TERRITORY.
-- * UNION (en niet UNION ALL): een dienst die op een dag al volgens de
--   weekdagen rijdt en daarnaast ook als extra dag vermeld staat, mag
--   maar één keer voorkomen.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_actieve_dienst AS
WITH dagen AS (
  SELECT (SELECT MIN(startdatum) FROM dienstregeling) + LEVEL - 1 AS datum
  FROM   dual
  CONNECT BY LEVEL <= (SELECT MAX(einddatum) - MIN(startdatum) + 1 FROM dienstregeling)
)
-- regelmatige dagen volgens de weekdagen, zonder de geschrapte dagen
SELECT d.datum, dr.service_id
FROM   dagen d
JOIN   dienstregeling dr ON d.datum BETWEEN dr.startdatum AND dr.einddatum
WHERE  DECODE(d.datum - TRUNC(d.datum, 'IW'),
              0, dr.maandag, 1, dr.dinsdag, 2, dr.woensdag, 3, dr.donderdag,
              4, dr.vrijdag, 5, dr.zaterdag, 6, dr.zondag) = 1
AND    NOT EXISTS (SELECT 1
                   FROM   dienstregeling_uitzondering u
                   WHERE  u.service_id = dr.service_id
                   AND    u.datum = d.datum
                   AND    u.uitzonderingstype = 2)
UNION
-- extra dagen
SELECT u.datum, u.service_id
FROM   dienstregeling_uitzondering u
WHERE  u.uitzonderingstype = 1
WITH READ ONLY;

-- ---------------------------------------------------------------------
-- 2. v_vertrekken: alle vertrekken per halte en per dienstdag
--    Hoofdview van de reisinfo-app.
--
-- Gebruik door de app (volgende vertrekken aan een halte):
--   SELECT * FROM v_vertrekken
--   WHERE  dienstdag = :datum AND halte_id = :halte AND vertrek_sec >= :nu
--   ORDER  BY vertrek_sec FETCH FIRST 10 ROWS ONLY;
-- Deze voorwaarden op halte_id en vertrek_sec gebruiken de index
-- idx_doortocht_halte_vertrek.
--
-- * dienstdag: de dag waarop de rit volgens de dienstregeling rijdt.
-- * vertrektijd_gtfs: zoals in GTFS, kan na middernacht > 24:00 zijn.
-- * vertrekmoment: het echte tijdstip. GTFS-tijden tellen vanaf het
--   begin van de dienstdag, dus dienstdag + seconden/86400 geeft het
--   juiste moment: 27:58 op 18/03 wordt 19/03 om 03:58.
-- * halte_naam_nl: valt terug op de Franse naam als er geen vertaling is.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_vertrekken AS
SELECT a.datum                                   AS dienstdag,
       d.halte_id,
       COALESCE(h.naam_nl, h.naam_fr)            AS halte_naam_nl,
       h.naam_fr                                 AS halte_naam_fr,
       d.vertrek_sec,
       LPAD(TRUNC(d.vertrek_sec / 3600), 2, '0') || ':' ||
       LPAD(MOD(TRUNC(d.vertrek_sec / 60), 60), 2, '0') AS vertrektijd_gtfs,
       a.datum + d.vertrek_sec / 86400           AS vertrekmoment,
       l.lijn_id,
       l.korte_naam                              AS lijn,
       vt.naam                                   AS vervoerstype,
       l.kleur,
       r.rit_id,
       r.bestemming,
       r.richting,
       d.volgnummer
FROM   doortocht d
JOIN   rit r               ON r.rit_id     = d.rit_id
JOIN   lijn l              ON l.lijn_id    = r.lijn_id
JOIN   vervoerstype vt     ON vt.type_id   = l.type_id
JOIN   halte h             ON h.halte_id   = d.halte_id
JOIN   v_actieve_dienst a  ON a.service_id = r.service_id
-- De laatste halte van een rit is een aankomst, geen vertrek: daar kan
-- je niet meer opstappen. De controle gebruikt de primaire sleutel
-- (rit_id, volgnummer) en is daardoor goedkoop.
WHERE  EXISTS (SELECT 1
                   FROM   doortocht d2
                   WHERE  d2.rit_id     = d.rit_id
                   AND    d2.volgnummer > d.volgnummer)
WITH READ ONLY;

-- ---------------------------------------------------------------------
-- 3. v_ritten_per_lijn_per_uur: rapport voor de analist
--    Hoeveel ritten vertrekken er per lijn, per dienstdag en per uur?
--
-- * Het vertrekuur van een rit = het vroegste vertrek van die rit.
-- * uur is het uur van de dienstdag en kan 24 tot 27 zijn (nachtritten).
-- * Deze view aggregeert over 1,5 miljoen doortochten en duurt dus een
--   tot enkele seconden. Voor een rapport is dat aanvaardbaar. Moet het
--   sneller, dan is een MATERIALIZED VIEW het alternatief: die slaat het
--   resultaat op en wordt enkel ververst wanneer de data verandert
--   (hier: bij een nieuwe import).
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_ritten_per_lijn_per_uur AS
SELECT a.datum                          AS dienstdag,
       l.lijn_id,
       l.korte_naam                     AS lijn,
       vt.naam                          AS vervoerstype,
       TRUNC(s.start_sec / 3600)        AS uur,
       COUNT(*)                         AS aantal_ritten
FROM   (SELECT rit_id, MIN(vertrek_sec) AS start_sec
        FROM   doortocht
        GROUP  BY rit_id) s
JOIN   rit r               ON r.rit_id     = s.rit_id
JOIN   lijn l              ON l.lijn_id    = r.lijn_id
JOIN   vervoerstype vt     ON vt.type_id   = l.type_id
JOIN   v_actieve_dienst a  ON a.service_id = r.service_id
GROUP  BY a.datum, l.lijn_id, l.korte_naam, vt.naam, TRUNC(s.start_sec / 3600)
WITH READ ONLY;

-- ---------------------------------------------------------------------
-- 4. v_actieve_storingen: lopende storingen met leesbare namen
--    Voor de app: toont enkel ACTIEVE storingen, zonder de interne
--    historiek (storing_log) of opgeloste storingen.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_actieve_storingen AS
SELECT s.storing_id,
       s.omschrijving,
       s.start_tijd,
       s.lijn_id,
       l.korte_naam                     AS lijn,
       s.halte_id,
       COALESCE(h.naam_nl, h.naam_fr)   AS halte_naam_nl,
       h.naam_fr                        AS halte_naam_fr
FROM   storing s
LEFT JOIN lijn  l ON l.lijn_id  = s.lijn_id    -- LEFT: een storing kan enkel over
LEFT JOIN halte h ON h.halte_id = s.halte_id   -- een lijn of enkel over een halte gaan
WHERE  s.status = 'ACTIEF'
WITH READ ONLY;

COMMENT ON TABLE v_actieve_dienst          IS 'Welke dienstregelingen rijden op welke datum (calendar + calendar_dates uitgerekend)';
COMMENT ON TABLE v_vertrekken              IS 'Alle vertrekken per halte en dienstdag, met lijn, bestemming en echt vertrekmoment';
COMMENT ON TABLE v_ritten_per_lijn_per_uur IS 'Rapport: aantal ritten per lijn, dienstdag en uur';
COMMENT ON TABLE v_actieve_storingen       IS 'Lopende storingen met leesbare lijn- en haltenamen';
