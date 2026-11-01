# Use case – MIVB reisinfo-databank

## Waarvoor wordt de databank gebruikt?

De databank is de backend van een reisinfo-app voor het Brusselse openbaar vervoer.
Ze bevat de echte dienstregeling van de MIVB (metro, tram en bus) en beantwoordt
de kernvraag van een reiziger: *welke vertrekken zijn er aan deze halte, op deze
dag, vanaf dit uur?*

De dienstregeling is een momentopname: de GTFS-feed van 16 maart tot 12 april 2026.
In een echte omgeving zou de MIVB-feed regelmatig opnieuw geladen worden, via
dezelfde staging en transformatie. Daarom is de import herhaalbaar.

Daarnaast kunnen reizigers hun favoriete haltes bewaren, en kunnen medewerkers van
de MIVB storingen melden per lijn of per halte. Analisten gebruiken dezelfde data
voor rapporten, bijvoorbeeld het aantal ritten per lijn per uur.

## Wie heeft toegang?

| Wie | Soort | Gebruikt de databank om |
|---|---|---|
| De reisinfo-app (`mivb_app`) | applicatie | vertrekken en storingen te tonen, reizigers te registreren en hun favorieten te bewaren |
| Beheerders (`mivb_beheerder`) | medewerkers | storingen in te voeren en op te lossen |
| Analisten (`mivb_analist`) | medewerkers | rapporten te maken over het aanbod |
| `MIVB` | eigenaar | het schema te bouwen, de dienstregeling in te laden en rechten op de objecten te geven |
| `SYSTEM` | DBA | de gebruikers en rollen aan te maken; dat vraagt systeemprivileges (CREATE USER, CREATE ROLE), die MIVB bewust niet heeft |

De reizigers zelf loggen niet in op de databank: zij gebruiken de app, en de app
spreekt de databank aan met één eigen account.

## Wat is de structuur?

Zie het conceptuele ERD ([erd_conceptueel.png](erd_conceptueel.png), of
[erd_conceptueel.drawio](erd_conceptueel.drawio) om te bewerken) en het fysieke
datamodel ([datamodel.md](datamodel.md)).

Het model bestaat uit twee delen:

- **De dienstregeling**, overgenomen uit GTFS. Een **lijn** (van een
  **vervoerstype**: tram, metro of bus) rijdt **ritten**. Een rit passeert een reeks
  **haltes**; elke passage is een **doortocht** met een aankomst- en vertrektijd.
  Op welke dagen een rit rijdt, staat in de **dienstregeling** met haar
  **uitzonderingen**. Een voorbeeld uit de data: op maandag 6 april 2026
  (Paasmaandag) vervalt de weekdagregeling (type 2) en rijdt er een
  zondagsregeling (type 1). Een halte kan bij een station horen.
- **De eigen toevoegingen.** Een **gebruiker** bewaart **favoriete haltes**
  (veel-op-veel). Een **storing** treft een lijn, een halte of allebei (minstens
  één van beide, afgedwongen met een CHECK-constraint), en elke wijziging eraan
  komt in de **storing_log**.

Daarnaast staan in het schema de **staging-tabellen** (`stg_...`): een ruwe kopie
van de GTFS-bestanden, met enkel VARCHAR2-kolommen. Ze dienen alleen voor de import;
de app en de andere gebruikers krijgen er geen rechten op.

## Welke features zijn nodig?

| Feature | Concept uit de les |
|---|---|
| Correcte, consistente data: elke rit hoort bij een bestaande lijn, elke doortocht bij een bestaande halte | DDL met constraints (PK, FK, UNIQUE, CHECK) |
| Automatische nummering van gebruikers, storingen en logregels | Sequences |
| Snel de vertrekken aan één halte opzoeken tussen 1,5 miljoen doortochten | Indexen |
| De app moet niet weten hoe dienstregelingen en uitzonderingen werken | Views (`v_vertrekken`, `v_actieve_storingen`, `v_ritten_per_lijn_per_uur`) |
| Een opgeloste storing krijgt automatisch een eindtijd; elke wijziging wordt gelogd | Triggers |
| Elke gebruiker ziet en doet enkel wat hij nodig heeft | Security: rollen en rechten |
| Scripts die bestaande objecten opruimen, en tests van de structuur | Data dictionary |

## Hoe zit het met de veiligheid?

Elke groep krijgt een eigen rol, volgens het principe van **least privilege**:

| Rol | Mag | Mag niet |
|---|---|---|
| `app_publiek` | vertrekken en actieve storingen lezen via views; gebruikers registreren, hun naam wijzigen en verwijderen; favorieten bewaren | de tabellen van de dienstregeling rechtstreeks lezen, een e-mailadres wijzigen, de auditlog zien |
| `beheerder` | storingen invoeren en wijzigen, de auditlog lezen | storingen verwijderen, in de auditlog schrijven, gebruikersgegevens zien |
| `analist` | alle data lezen voor rapporten | persoonsgegevens (gebruikers en favorieten) zien, iets wijzigen |

- De app leest de **vertrekken en storingen enkel via views** (`v_vertrekken`,
  `v_actieve_storingen`); de onderliggende tabellen (rit, doortocht, dienstregeling,
  storing) ziet ze niet. Halte, lijn en vervoerstype leest ze rechtstreeks, en
  gebruiker en favoriete_halte beheert ze rechtstreeks.
- **Kolomrechten** beperken wat er gewijzigd mag worden (bijvoorbeeld enkel de naam van een gebruiker).
- De **auditlog** wordt enkel door een trigger gevuld en kan niet vervalst worden
  door de app of de beheerders. De eigenaar MIVB en de DBA (SYSTEM) kunnen dat wel;
  zij moeten dus vertrouwd worden.
- **Privacy:** persoonsgegevens zijn onzichtbaar voor analisten, en een gebruiker
  kan verwijderd worden (recht op vergetelheid); zijn favorieten verdwijnen mee.

Details en motivatie: [ontwerpkeuzes.md](ontwerpkeuzes.md), sectie Security.
