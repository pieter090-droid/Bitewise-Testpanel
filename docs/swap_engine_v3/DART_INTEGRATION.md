# Swap Engine v3 — Dart-integratie

## Status

De rekenkern is als pure Dart-module toegevoegd naast de bestaande engine. De
compile-time featureflag `SWAP_ENGINE_V3_ENABLED` staat standaard uit. De
bestaande UI, kandidaatselectie en Supabase-configuratie zijn niet gewijzigd.

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

## Nog niet activeren

Voor runtime-activatie ontbreken nog:

1. de acht goedgekeurde v3-swaptabellen of een gelijkwaardig lokaal contract;
2. specifieke `direct_swap_group_code`-waarden in plaats van brede oude
   `swap_family`-waarden;
3. een concrete repository/RPC-mapper;
4. gevalideerde groepsrelaties, compatibiliteitsregels en guardrails;
5. UI-mapping van `SwapCalculationResultV3`.

De 14 MB prototype-JSON is bewust niet als Flutter-webasset toegevoegd. Dat zou
de download onnodig zwaar maken en voorlopige data als productiebron behandelen.

## Activatie

Na database- en datareview kan een repository-implementatie worden toegevoegd.
De testbuild kan v3 dan activeren met:

```text
--dart-define=SWAP_ENGINE_V3_ENABLED=true
```

V2 en v3 mogen nooit in één aanbevelingslijst worden gemengd.
