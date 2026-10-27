# Datamodel – MIVB reisinfo-databank

Fysiek datamodel zoals het in Oracle gebouwd wordt (sql/02_model_tabellen.sql). Het conceptuele ERD staat in erd_conceptueel.png.
Dit diagram rendert automatisch op GitHub (Mermaid). Lengtes van datatypes staan in de commentaar.

```mermaid
erDiagram
    vervoerstype ||--o{ lijn : "heeft"
    lijn ||--o{ rit : "rijdt"
    dienstregeling ||--o{ rit : "bepaalt wanneer"
    dienstregeling ||--o{ dienstregeling_uitzondering : "heeft"
    rit ||--|{ doortocht : "passeert"
    halte ||--o{ doortocht : "bediend door"
    halte |o--o{ halte : "is station van"
    gebruiker ||--o{ favoriete_halte : "bewaart"
    halte ||--o{ favoriete_halte : "is favoriet in"
    lijn |o--o{ storing : "getroffen door"
    halte |o--o{ storing : "getroffen door"
    storing ||..o{ storing_log : "gelogd in (geen FK)"

    vervoerstype {
        NUMBER type_id PK "NUMBER(2) - 0 tram, 1 metro, 3 bus"
        VARCHAR2 naam "VARCHAR2(20) NOT NULL"
    }

    lijn {
        VARCHAR2 lijn_id PK "VARCHAR2(10) - GTFS route_id"
        VARCHAR2 korte_naam "VARCHAR2(10) - bv. 1, 92"
        VARCHAR2 lange_naam_fr "VARCHAR2(100)"
        VARCHAR2 lange_naam_nl "VARCHAR2(100) - uit translations"
        NUMBER type_id FK "NUMBER(2)"
        CHAR kleur "CHAR(6) - hex"
        CHAR tekstkleur "CHAR(6) - hex"
    }

    dienstregeling {
        VARCHAR2 service_id PK "VARCHAR2(10)"
        NUMBER maandag "NUMBER(1) CHECK 0/1"
        NUMBER dinsdag "NUMBER(1) CHECK 0/1"
        NUMBER woensdag "NUMBER(1) CHECK 0/1"
        NUMBER donderdag "NUMBER(1) CHECK 0/1"
        NUMBER vrijdag "NUMBER(1) CHECK 0/1"
        NUMBER zaterdag "NUMBER(1) CHECK 0/1"
        NUMBER zondag "NUMBER(1) CHECK 0/1"
        DATE startdatum
        DATE einddatum
    }

    dienstregeling_uitzondering {
        VARCHAR2 service_id PK, FK "VARCHAR2(10)"
        DATE datum PK
        NUMBER uitzonderingstype "NUMBER(1) CHECK 1=toegevoegd, 2=geschrapt"
    }

    halte {
        VARCHAR2 halte_id PK "VARCHAR2(10) - voorloopnullen!"
        VARCHAR2 naam_fr "VARCHAR2(100)"
        VARCHAR2 naam_nl "VARCHAR2(100) - uit translations"
        NUMBER breedtegraad "NUMBER(9,6)"
        NUMBER lengtegraad "NUMBER(9,6)"
        NUMBER locatietype "NUMBER(1) - 0 halte, 1 station"
        VARCHAR2 station_id FK "VARCHAR2(10) - verwijst naar halte"
    }

    rit {
        VARCHAR2 rit_id PK "VARCHAR2(20) - GTFS trip_id"
        VARCHAR2 lijn_id FK "VARCHAR2(10)"
        VARCHAR2 service_id FK "VARCHAR2(10)"
        VARCHAR2 bestemming "VARCHAR2(100) - trip_headsign"
        NUMBER richting "NUMBER(1) CHECK 0/1"
    }

    doortocht {
        VARCHAR2 rit_id PK, FK "VARCHAR2(20)"
        NUMBER volgnummer PK "NUMBER(3) - stop_sequence"
        VARCHAR2 halte_id FK "VARCHAR2(10)"
        NUMBER aankomst_sec "NUMBER(6) - seconden sinds middernacht"
        NUMBER vertrek_sec "NUMBER(6) - kan > 86400 zijn"
    }

    gebruiker {
        NUMBER gebruiker_id PK "NUMBER(10) - DEFAULT seq_gebruiker.NEXTVAL"
        VARCHAR2 email UK "VARCHAR2(255) NOT NULL"
        VARCHAR2 naam "VARCHAR2(100)"
        DATE aangemaakt_op "DEFAULT SYSDATE"
    }

    favoriete_halte {
        NUMBER gebruiker_id PK, FK
        VARCHAR2 halte_id PK, FK "VARCHAR2(10)"
        DATE toegevoegd_op "DEFAULT SYSDATE"
    }

    storing {
        NUMBER storing_id PK "NUMBER(10) - DEFAULT seq_storing.NEXTVAL"
        VARCHAR2 lijn_id FK "nullable"
        VARCHAR2 halte_id FK "nullable - CHECK minstens lijn of halte"
        VARCHAR2 omschrijving "VARCHAR2(500) NOT NULL"
        TIMESTAMP start_tijd "DEFAULT SYSTIMESTAMP"
        TIMESTAMP eind_tijd "nullable"
        VARCHAR2 status "VARCHAR2(10) DEFAULT ACTIEF, CHECK ACTIEF/OPGELOST"
    }

    storing_log {
        NUMBER log_id PK "NUMBER(10) - DEFAULT seq_storing_log.NEXTVAL"
        NUMBER storing_id "bewust geen FK"
        VARCHAR2 actie "VARCHAR2(10) - INSERT/UPDATE/DELETE"
        VARCHAR2 oude_status "VARCHAR2(10)"
        VARCHAR2 nieuwe_status "VARCHAR2(10)"
        VARCHAR2 gewijzigd_door "VARCHAR2(128) DEFAULT USER"
        TIMESTAMP gewijzigd_op "DEFAULT SYSTIMESTAMP"
    }
```
