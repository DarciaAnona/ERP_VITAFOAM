# VITAFOAM ERP intégré — Supabase

Cette version fusionne le précédent ERP Articles / Stock / Budget avec le circuit de production :

**Nomenclature Bloc → OF → Viking/Séchoir → Débitage/Tamponnage → Confection → Stock PF**

## 1. Initialiser Supabase

Le frontend est déjà configuré sur le projet Supabase :

`https://vgmcwpoinnuzjkkzntmt.supabase.co`

Dans **Supabase > SQL Editor**, ouvrir `supabase/setup.sql`, copier tout le script et l'exécuter.

> IMPORTANT : `setup.sql` réinitialise les tables du prototype `public` concernées par cet ERP. Il faut donc l'utiliser sur le projet de développement/prototype ou après sauvegarde des données utiles.

Le script crée :
- le référentiel Articles commun au stock et à la production ;
- les nomenclatures Bloc et leurs composants MP ;
- les OF et le gel de leur standard ;
- Viking/Séchoir et les pesées ;
- Débitage/Tamponnage, conforme, souple et chutes ;
- Confection et consommations PSF ;
- les mouvements de stock ;
- les fonctions Supabase RPC qui sécurisent les validations métier ;
- la vue de synthèse des OF.

## 2. Installer / démarrer

Dans PowerShell :

```powershell
npm install
npm run dev
```

Puis ouvrir :

`http://localhost:5173/`

Si `node_modules` est déjà présent dans votre ancien dossier Vite, vous pouvez remplacer les fichiers par ceux de cette version puis lancer directement `npm install` une fois pour synchroniser les dépendances.

## 3. Test conseillé

1. **Nomenclatures** : sélectionner BLOC SGA et vérifier/remplacer le standard exemple.
2. **Nouvel OF Bloc** : créer un OF SGA.
3. Ouvrir l'OF depuis **Production**.
4. **Viking/Séchoir** : saisir consommations réelles, blocs, chutes et poids de chaque bloc après séchage.
5. **Débitage** : saisir conforme, souple, croûte, chemelle, filement, autres. L'écart matière doit être ≤ 0,05 kg.
6. **Confection** : traiter les sorties. Le souple impose automatiquement **gaine seule**.
7. **Stock** : vérifier les sorties MP et l'entrée PF.
8. **Budget** : actualiser la valorisation.

## 4. Règles métier déjà automatisées

- N° OF automatique.
- Nomenclature active copiée/figée dans l'OF.
- Besoin MP théorique = standard par bloc × blocs prévus.
- Valeur consommation = quantité réelle × PRU.
- Nombre de pesées = nombre de blocs conformes.
- Poids total après séchage transmis automatiquement au Débitage.
- Bilan matière Débitage obligatoire.
- Souple = chute valorisable de la ligne, mais transférable à Confection.
- Souple → gaine seule.
- PF + rebut = quantité entrée en Confection.
- Entrée PF et sorties MP/PSF créées automatiquement dans les mouvements de stock.
- Les transferts internes ne sont pas comptés comme entrée/sortie globale dans l'état de stock.

## 5. Sécurité

La version fournie est volontairement en **mode prototype** avec des policies RLS ouvertes à `anon` afin de fonctionner immédiatement avec la clé publique. Avant un déploiement réel en usine, activer Supabase Auth et créer des rôles (Admin, Viking, Débitage, Confection, Magasin, CDG) avec des policies RLS restrictives.
