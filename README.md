# ForeverDex

ForeverDex est un carnet de collection pour World of Warcraft: Forever. Ouvrez-le avec `/foreverdex` ou avec l’icône de la mini-carte. Ciblez un joueur pour ajouter son prénom et son nom de famille, ou faites un clic droit sur son pseudo dans le chat puis **Ajouter au ForeverDex** (le niveau et la guilde ne sont alors pas connus).

Le carnet contient 112 combinaisons de race, de classe et de sexe, puis 39 emplacements bonus libres. Capturer un autre personnage sur une carte classique déjà occupée propose de la remplacer ou d’ajouter ce personnage en bonus. Pour remplir un bonus, choisissez l’onglet **Bonus**, puis **Ajouter en bonus**. Un clic droit sur une carte classique l’envoie dans les bonus. L’étoile d’une carte l’ajoute à l’onglet **Favoris** (`entry.favorite` dans la sauvegarde).

Pour comparer deux collections, faites un clic droit sur un portrait de joueur, un membre du groupe ou du raid, ou un pseudo dans le chat, puis **Comparer nos captures**. `/foreverdex comparer` fait la même chose avec la cible et peut servir dans une macro.

## Organisation du code

Le fichier `ForeverDex.toc` charge les modules dans cet ordre. Ils partagent la table privée fournie par WoW à l’addon.

| Fichier | Responsabilité |
| --- | --- |
| `Locale.lua` | Libellés français et anglais. Le client `frFR` utilise le français, les autres utilisent l’anglais. Les noms de classe proviennent du client. |
| `Art.lua` | Textures, atlas et sons du client, avec une ressource de secours quand un atlas manque. `/foreverdex textures` liste les atlas absents. |
| `Catalog.lua` | Combinaisons jouables, thèmes des cartes, recherche, filtres et tri. |
| `Collection.lua` | Lecture de la cible, migration de la sauvegarde, ajout et remplacement des cartes. |
| `Duel.lua` | Comparaison entre deux joueurs équipés de ForeverDex : demande, accord, échange par messages d’addon chuchotés et écran de duel. |
| `UI.lua` | Fenêtre façon Journal des donjons : liste des races, grille de cartes, fiche détaillée, onglets et capture. |
| `CaptureVisuals.lua` | Animation de capture : lancer sur le portrait, absorption, rebonds, trois secousses, déclic, retour vers l’icône de la mini-carte, puis notification montant du bas de l’écran. |
| `Settings.lua` | Paramètres (Options → AddOns → ForeverDex, `/foreverdex options` ou clic droit sur l’icône de la mini-carte). |
| `Media/Ball.tga` | Orbe de capture ForeverDex, dessinée pour l’addon (une seule image, pour pouvoir pivoter). |
| `Media/Icon.tga` | Icône de l’addon (liste des addons, mini-carte, portrait de la fenêtre). |
| `ForeverDex.lua` | Initialisation après le chargement de la sauvegarde, événements du jeu, commande et bouton de mini-carte. |

## Sauvegarde

`ForeverDexDB.cards` associe chaque carte à une clé stable. Une combinaison utilise les identifiants numériques du jeu (`race:classe:sexe`). Un bonus utilise `bonus:n` et conserve sa combinaison d’origine. Les libellés traduits ne participent pas aux clés.

`ForeverDexDB.version` indique le format de la sauvegarde. Pour le modifier, augmentez `DB_VERSION` dans `Collection.lua` et ajoutez une conversion à `migrations`, sans changer celles déjà publiées. Testez-la sur une copie d’une vraie sauvegarde avant de publier.

Depuis la version 1.3, une capture enregistre aussi la date, la zone, le niveau et la guilde quand le client les fournit.

Le portrait personnalisé est affiché à partir de la cible. La sauvegarde conserve l’identité du personnage et sa combinaison. Lorsque le joueur n’est plus ciblé, le médaillon affiche le portrait générique de la race.

## Compatibilité des comparaisons

Deux joueurs doivent pouvoir comparer leurs collections avec des versions différentes. Ne modifiez jamais la forme des messages `Q`, `A`, `N` et `D` de `Duel.lua`. Pour ajouter une donnée, créez un nouveau type de message (ignoré par les anciennes versions) ou ajoutez un champ après une tabulation dans un élément existant. Les cartes dont la clé est inconnue du catalogue sont ignorées à la réception.

## Vérification en jeu

Rechargez l’interface avec `/reload`. Vérifiez l’ouverture depuis la mini-carte, la recherche par nom complet, le remplacement d’une carte et l’ajout d’un bonus. Le changement de cible doit rétablir le portrait générique. Testez sur un client français et un client anglais pour contrôler les libellés, les infobulles et la confirmation.
