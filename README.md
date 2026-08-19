# VITAFOAM ERP — Supabase — Version 3.0.0

Cette version contient les modules déjà développés : Articles, Production, Nomenclatures, OF Bloc, Viking/Séchoir, Débitage/Tamponnage, Confection, Stock et Budget.

## Nouvelle règle Article / Société / Site

Pour tout article **géré en stock**, le site principal est automatique et obligatoire :

- `VT` → `VITA` → **Vitafoam Tana**
- `VD` → `VIDIE` → **Vitafoam Diego**
- `VS` → `VISA` → **Vitafoam Sambava**

Lors de la création, l'utilisateur choisit le code société mais **ne choisit plus librement le site principal**. L'ERP l'affecte automatiquement.

Pour rattacher un article déjà existant à un autre site :

1. Ouvrir l'article.
2. Cliquer sur **Modifier**.
3. Dans **Article site**, les sites déjà rattachés sont cochés et verrouillés.
4. Cocher le ou les nouveaux sites : Vitafoam Tana, Vitafoam Diego, Vitafoam Sambava.
5. Cliquer sur **Enregistrer / rattacher**.

Le code article reste unique. L'ERP ajoute seulement un rattachement dans `article_sites`.

## SQL Supabase

### Base Supabase déjà utilisée par l'ERP (recommandé)

Copier-coller dans **Supabase > SQL Editor** le fichier :

`SUPABASE_SQL_A_COPIER.sql`

Cette migration est **non destructive** : elle conserve les articles, stocks, OF et données de production existants.

### Nouvelle base vide uniquement

Utiliser :

`SUPABASE_SQL_COMPLET_NOUVELLE_BASE.sql`

Attention : le script complet contient le setup prototype qui réinitialise les tables de l'ERP.

## Lancer localement

```powershell
npm install
npm run dev
```

Puis ouvrir l'URL affichée par Vite, normalement `http://localhost:5173/`.

## Build Vercel

```powershell
npm run build
```

Paramètres Vercel :

- Framework Preset : Vite
- Build Command : `npm run build`
- Output Directory : `dist`
- Install Command : `npm install`

`integrated.js` est chargé en `type="module"` pour que Vite l'intègre correctement au build de production.

## Contrôle de version

Dans la console du navigateur, cette version affiche :

`[VITAFOAM ERP] Version 3.0.0 — rattachement multi-sites articles`

Cela permet de vérifier rapidement que Vercel sert bien la dernière version.
