# Swap Engine v3 — Dart-integratie

## Status

De rekenkern is als pure Dart-module toegevoegd naast de bestaande engine. Een
read-only repository kan een compacte, meegebouwde testdataset met 9.019
producten laden en de uitkomst naar de bestaande UI vertalen. De compile-time
featureflag `SWAP_ENGINE_V3_ENABLED` staat standaard uit. Supabase wordt door
dit testpad niet gelezen of gewijzigd en v2/v3-resultaten worden nooit gemengd.

## Veilige grens

`SwapCandidateRepositoryV3` levert één compleet, reeds gescheiden inputpakket:
bronproduct, directe kandidaten, expliciet gerelateerde alternatieven en alle
policydata. `SwapCalculatorV3` kent geen database, netwerk, Riverpod of UI.

De volgorde is:

1. bron en policy valideren;
2. kandidaatsemantiek en gebruiksrol valideren;
3. vergelijkingsbasis bepalen;
4. guardrails uitvoeren;
5. doelverbetering en deelscores berekenen;
6. minimumscore per lane toepassen;
7. per lane deterministisch dedupliceren, sorteren en beperken;
8. feitelijke uitleg opbouwen.

## Correcties ten opzichte van het Node-prototype

- Een stukportie gebruikt het bekende stukgewicht en nooit het getal `1` als
  gramgewicht.
- Massa en volume zijn zonder dichtheid onvergelijkbaar.
- Er is geen automatische `per_100g`-fallback voor vloeistoffen.
- Onbekende vorm of bereidingsstatus faalt gesloten.
- Afwijkende vorm/status vereist een expliciete, directionele regel.
- Alternatieven vereisen een expliciete, actieve en directionele groepsrelatie
  voor de juiste lane en gebruiksrol.
- De bron moet zelf eligible, classified en voldoende betrouwbaar zijn.
- Relatiedrempels voor minimale verbetering en score worden afgedwongen.
- Groepsbeleid bepaalt de gewenste vergelijkingsbasis.

## Tijdelijke testdataset

`assets/data/swap_dataset_v3_test.json` wordt reproduceerbaar gebouwd met:

```text
node scripts/swap_engine_v3/build_flutter_test_asset.js
```

Directe groepen bestaan in deze testlaag uit hoofdcategorie, productcategorie,
subcategorie, vorm, bereidingsstatus, een gecontroleerd producttype voor brede
subcategorieën en de actieve gebruiksrol. Andere producttypen binnen zo'n brede
subcategorie komen uitsluitend in de lane `compatibleAlternative` terecht.
Legacy `swap_family` wordt alleen gebruikt om tijdelijke, expliciete relaties
naar andere productfamilies te construeren.

Dit is testdata, geen goedgekeurde productiebron. Voor productie ontbreken nog:

1. de acht goedgekeurde v3-swaptabellen of een gelijkwaardig lokaal contract;
2. volledige review van producttypen, relaties, porties en guardrails;
3. een productie-repository/RPC-mapper;
4. feedback uit de gecontroleerde testbuild.

## Activatie

Een losse HTML-testbuild wordt zo gemaakt:

```text
flutter build web --release --dart-define=SWAP_ENGINE_V3_ENABLED=true --base-href /Bitewise-Testpanel/
```

Zonder de dart-define blijft de huidige engine actief. In v3-testmodus toont de
interface expliciet een testbanner en wordt dagcontext verborgen omdat v3 die
nog niet meeneemt.
