# Bitewise Testpanel

Afzonderlijke, branded testpanelversie van Bitewise. De bestaande Bitewise-
repository en webapp blijven ongewijzigd en kunnen altijd opnieuw gebruikt
worden.

## Testpanelprincipes

- Persoonlijke data en feedback blijven standaard lokaal in de browser.
- Cloudsync staat standaard uit en vereist expliciete toestemming.
- Analytics staat uit.
- De app gebruikt alleen de publishable Supabase-key, nooit een service-role
  key.
- Producten en classificatie worden read-only uit
  `product_features_resolved` gelezen.
- Swaps worden regelgebaseerd, deterministisch en zonder AI-aanroep berekend.
- Onbekende waarden tellen nooit als nul.
- Niet-geclassificeerde of niet-swaprelevante producten worden geweigerd.
- Bij twijfel toont Bitewise liever geen swap.
- Allergenen- en productinformatie moet altijd op het etiket worden nagekeken.

De map `supabase/migrations/` is uitsluitend reproduceerbare projectgeschiedenis.
De GitHub-workflows voeren geen migraties, databasepushes of functiondeployments
uit. Pas Supabase alleen aan na een afzonderlijke review en expliciete
goedkeuring.

## Kwaliteitscontroles

Iedere Pages-publicatie voert uit:

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-fatal-infos
flutter test
flutter build web --release
```

## Lokaal starten

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run -d chrome \
  --dart-define=SUPABASE_URL=... \
  --dart-define=SUPABASE_ANON_KEY=...
```

## Feedback

Bij iedere swap kan de tester duim omhoog of omlaag geven. Negatieve feedback
kan worden voorzien van een reden en toelichting. In **Instellingen > Feedback
kopiëren** kan de tester een privacyarm JSON-rapport kopiëren en delen. Het
rapport bevat barcodes, gekozen doel, reden, toelichting, tijdstip en
appversie—geen naam of profiel.

## Branding

De bestaande Bitewise-huisstijl blijft behouden: navy `#0D1B2A`, goud
`#C9A84C`, rustig, premium en betrouwbaar.
