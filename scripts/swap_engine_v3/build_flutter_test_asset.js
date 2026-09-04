#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..', '..');
const sourcePath = path.join(
  root,
  'artifacts',
  'swap_engine_v3',
  'swap_dataset_v3.json',
);
const outputPath = path.join(
  root,
  'assets',
  'data',
  'swap_dataset_v3_test.json',
);
const source = JSON.parse(fs.readFileSync(sourcePath, 'utf8'));

function normalizedName(product) {
  return `${product.name || ''} ${product.brand || ''}`
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase();
}

function has(text, pattern) {
  return pattern.test(text);
}

// Extra producttype binnen subcategorieën die aantoonbaar meerdere, niet-
// directe productsoorten bevatten. Dit is een generieke regel over alle
// producten in zo'n subcategorie; er staan bewust geen barcodes in.
function directType(product) {
  const name = normalizedName(product);
  switch (product.productSubcategoryCode) {
    case 'creamy_table_sauces':
      if (has(name, /\b(whisk(?:e)?y|cocktail)\b/)) return 'cocktail_sauce';
      if (has(name, /\b(knoflook|garlic|aioli)\b/)) return 'garlic_sauce';
      if (has(name, /\b(friet|frites|fritessaus|fries)\b/)) return 'fries_sauce';
      if (has(name, /\b(mayo(?:naise)?|mayonnaise)\b/)) return 'mayonnaise';
      if (has(name, /\b(mosterd|mustard)\b/)) return 'mustard_sauce';
      return 'other_creamy_sauce';
    case 'soft_drinks':
      if (has(name, /\b(cola|coke|pepsi)\b/)) return 'cola';
      if (has(name, /\b(tonic)\b/)) return 'tonic';
      if (has(name, /\b(ginger ale|ginger beer)\b/)) return 'ginger';
      if (has(name, /\b(sinas|orange|orangina)\b/)) return 'orange_soda';
      if (has(name, /\b(7up|sprite|lemon[- ]?lime|citroen|lemon)\b/)) {
        return 'lemon_lime_soda';
      }
      if (has(name, /\b(cassis)\b/)) return 'cassis';
      if (has(name, /\b(bitter lemon)\b/)) return 'bitter_lemon';
      return 'other_soft_drink';
    case 'yoghurt_skyr_quark':
      if (has(name, /\b(skyr)\b/)) return 'skyr';
      if (has(name, /\b(kwark|quark)\b/)) return 'quark';
      if (has(name, /\b(griekse|greek)\b/)) return 'greek_yoghurt';
      return 'yoghurt';
    case 'plant_drinks':
      if (has(name, /\b(haver|oat)\b/)) return 'oat_drink';
      if (has(name, /\b(soja|soy)\b/)) return 'soy_drink';
      if (has(name, /\b(amandel|almond)\b/)) return 'almond_drink';
      if (has(name, /\b(kokos|coconut)\b/)) return 'coconut_drink';
      if (has(name, /\b(rijst|rice)\b/)) return 'rice_drink';
      return 'other_plant_drink';
    case 'cold_cuts':
      if (has(name, /\b(kip|chicken|kalkoen|turkey)\b/)) return 'poultry_cold_cuts';
      if (has(name, /\b(ham|prosciutto)\b/)) return 'ham';
      if (has(name, /\b(salami|chorizo)\b/)) return 'salami';
      if (has(name, /\b(roastbeef|rund|beef|ossenworst)\b/)) return 'beef_cold_cuts';
      if (has(name, /\b(bacon|spek)\b/)) return 'bacon';
      return 'other_cold_cuts';
    default:
      return 'standard';
  }
}

const products = source.products
  .filter((product) => product.swapEligible)
  .map((product) => ({
    b: product.barcode,
    n: product.name,
    brand: product.brand,
    main: product.mainCategoryCode,
    cat: product.productCategoryCode,
    sub: product.productSubcategoryCode,
    family: product.directSwapGroupCode,
    form: product.productFormCode,
    prep: product.preparationStatusCode,
    type: directType(product),
    primaryRole: product.primaryUsageRoleCode,
    roles: product.usageRoleCodes,
    confidence: product.classificationConfidence,
    completeness: product.dataCompleteness,
    nutrition: [
      product.nutrition.energyKcalPer100,
      product.nutrition.proteinGPer100,
      product.nutrition.carbohydratesGPer100,
      product.nutrition.sugarsGPer100,
      product.nutrition.fatGPer100,
      product.nutrition.saturatedFatGPer100,
      product.nutrition.fiberGPer100,
      product.nutrition.saltGPer100,
    ],
    portion: product.portionContext
      ? [
          product.portionContext.value,
          product.portionContext.unit,
          product.portionContext.confidence,
          product.portionContext.pieceWeightG,
          product.portionContext.individualOrShareable,
        ]
      : null,
  }));

const output = {
  datasetVersion: 'legacy_bridge_flutter_v3_test_2',
  provisional: true,
  policyVersion: source.policyVersion,
  products,
  relations: source.relations.map((relation) => ({
    sourceFamily: relation.sourceGroupCode,
    targetFamily: relation.targetGroupCode,
    role: relation.usageRoleCode,
    semanticFit: relation.semanticFit,
    minimumImprovement: relation.minimumGoalImprovementPct,
    minimumScore: relation.minimumCandidateScore,
    active: relation.isActive,
  })),
  guardrails: source.guardrails,
  defaultProfile: source.defaultProfile,
  attributeCompatibility: source.attributeCompatibility,
};

fs.mkdirSync(path.dirname(outputPath), { recursive: true });
fs.writeFileSync(outputPath, JSON.stringify(output));
console.error(
  `OK — ${products.length} tijdelijke v3-producten, ` +
    `${output.relations.length} legacy-relaties, ` +
    `${fs.statSync(outputPath).size} bytes`,
);
