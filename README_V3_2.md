# VITAFOAM ERP v3.2

## Nouveautés

### Nomenclatures
- Bouton **Retour Production**.
- Bouton **Créer une nomenclature**.
- Lors de la création d'une nouvelle nomenclature, l'ERP propose automatiquement la version suivante.
- La version active précédente est conservée dans l'historique et désactivée.
- La nouvelle version devient la référence des prochains OF.

### Production — Extraction Analyse CDG
Filtres disponibles :
- Date début / date fin
- Site VITA / VIDIE / VISA
- Statut OF
- Bloc / famille OF
- N° OF

Colonnes d'extraction :
- Étape
- N° OF
- Date
- Site
- Article produit
- Désignation
- Quantité prévue m3
- Quantité réelle m3
- Quantité prévue kg
- Quantité réelle kg
- Type consommation MP / PSF
- MP / PSF consommé
- Quantité consommée
- Unité
- PRU
- Valeur

Règles de calcul :
- Prévu m3 Viking/Bloc = volume standard article Bloc × nombre de blocs prévus.
- Prévu kg Viking/Bloc = somme des lignes standard OF dont l'unité est kg.
- Réel kg Viking/Bloc = somme des pesées des blocs après séchage.
- Réel m3 Viking/Bloc = volume standard article Bloc × nombre de blocs pesés.
- Réel m3 Confection/PF = quantité PF réalisée × volume mousse de l'article PF.
- Réel kg Confection/PF = poids de la sortie Débitage affecté au lot au prorata des pièces traitées.
- Le prévu m3/kg PF reste vide tant qu'un mix de produits finis prévu n'est pas enregistré dans l'OF.

## Base Supabase
Aucune migration SQL supplémentaire n'est requise par rapport à la v3/v3.1.

## Lancement
```powershell
npm install
npm run dev
```

## Build Vercel
```powershell
npm run build
```
Vercel : Framework Vite, Build Command `npm run build`, Output Directory `dist`.
