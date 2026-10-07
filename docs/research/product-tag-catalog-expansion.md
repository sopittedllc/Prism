# Bundled product tag catalog expansion — 2026-10-06

The canonical v2 resource contains 200 plugin and 200 sample-library product records. The original 100 records were retained as reviewed values. The added 300 records are a representative starter selection from user priorities and official makers; this is not a measured popularity ranking. Matching a catalog record is never proof of installation, use, or license ownership. All additions are offline-only and use the existing exact maker/product identity rules.

# Plugin expansion source notes

Artifact: `Sources/SimplifyCore/Resources/product-tag-catalog-v2.json` (150 new plugin records; existing bundled 50 excluded). This is a representative starter set from the user’s preferred product pool, not a global popularity ranking. Each record is offline-only, names one product, uses concise paraphrased evidence, and points to an official product page or official maker catalog. The official page establishes identity and only the stated broad plugin purpose; no marketing copy is reproduced.

## Official sources used

- Sonnox Oxford catalog: https://sonnox.com/oxford/ — Oxford EQ, Inflator, Limiter, SuprEsser, TransMod, Drum Gate 2, and Envolution.
- Waves plugin catalog and product listings: https://www.waves.com/plugins — API 550A/550B, API 560, SSL, CLA, Renaissance, L/H-series, Kramer/J37, vocal, restoration, and mastering entries. The catalog’s product titles and category descriptions support the record-level product facts.
- Universal Audio UAD Complete inventory: https://help.uaudio.com/hc/en-us/articles/4410297696916-What-plug-ins-are-included-in-UAD-Complete-4 — exact UAD product names and inventory categories, including native and DSP titles. Product function tags stay at the broad category level.
- Eventide H9 catalog: https://www.eventideaudio.com/plug-ins-h9-series/; Signature Effects catalog: https://www.eventideaudio.com/plug-ins-signature-effects/; SplitEQ product page: https://www.eventideaudio.com/plug-ins/spliteq/ — individual effect names and their effect categories.
- Arturia effects catalog: https://www.arturia.com/store/software-effects; Pigments: https://www.arturia.com/products/software-instruments/pigments/overview — named effects and a software synth.
- Softube Producer Collection: https://www.softube.com/uk/plug-ins/producer-collection; Mixing catalog: https://cdn.softube.com/us/plug-ins/mixing?ChannelSwitch=true; Weiss DS1-MK3: https://www.softube.com/ds1 — standalone plug-in names and processing roles.
- Plugin Alliance official pages: https://www.plugin-alliance.com/products/bx_console-ssl-4000-e, https://www.plugin-alliance.com/products/bx_console-ssl-4000-g, https://www.plugin-alliance.com/products/bx_console-ssl-9000-j, https://www.plugin-alliance.com/products/triad, https://www.plugin-alliance.com/products/sandman-pro — channel-strip and effect identities.
- LiquidSonics downloads/software catalog: https://www.liquidsonics.com/downloads/ — current reverb products and editions.
- Tokyo Dawn Records: https://www.tokyodawn.net/tdr-nova/free/, https://www.tokyodawn.net/tdr-kotelnikov/, https://www.tokyodawn.net/tdr-molot-ge/ — EQ and compressor identities.
- Voxengo downloads: https://www.voxengo.com/downloads/ — GlissEQ, Elephant, and SPAN Plus.
- Soundtoys: https://www.soundtoys.com/product/soundtoys-5/, https://www.soundtoys.com/wp-content/uploads/Soundtoys-Users-Guide.pdf, https://www.soundtoys.com/product/devil-loc-deluxe/ — SuperPlate, PhaseMistress, and Devil-Loc Deluxe.
- Baby Audio: https://babyaud.io/complete-bundle — Crystalline, Comeback Kid, IHNY-2, and Smooth Operator Pro.
- oeksound: https://oeksound.com/plugins/soothe2/, https://oeksound.com/plugins/spiff — resonance control and transient shaping.
- Soundtheory: https://www.soundtheory.com/gullfoss, https://www.soundtheory.com/kraftur — equalization and soft clipping.
- McDSP plugin index: https://mcdsp.com/plugin-index/ — FilterBank, CompressorBank, and MC2000.
- SIR Audio Tools StandardCLIP: https://www.siraudiotools.com/product.php?id=standardclip — clipping purpose and current product identity.
- Cytomic The Glue: https://cytomic.com/product/glue/ — bus-compressor identity.
- Output products: https://output.com/products — Thermal, Movement, and Arcade product identities and purposes.
- Goodhertz plugin catalog: https://goodhertz.com/plugins/ — Vulf Compressor and Wow Control.
- Sound Radix: https://www.soundradix.com/shop/ — Auto-Align 2 and SurferEQ 2.
- Native Instruments Kontakt 8: https://www.native-instruments.com/products/kontakt; Guitar Rig 7 Pro: https://www.native-instruments.com/products/komplete/guitar-rig-7-pro/.
- Spectrasonics Omnisphere 3, Keyscape, and Trilian: https://www.spectrasonics.net/products/omnisphere/overview.php, https://www.spectrasonics.net/products/keyscape/, https://www.spectrasonics.net/products/trilian/overview.php.
- Xfer Records Serum 2: https://www.xferrecords.com/products/serum-2.
- Modartt Pianoteq 9: https://www.modartt.com/pianoteq_overview.
- LennarDigital Sylenth1: https://www.lennardigital.com/sylenth1/.
- XLN Audio Addictive Drums 2: https://www.xlnaudio.com/products/addictive_drums_2.
- Toontrack Superior Drummer 3, EZdrummer 3, and EZbass: https://www.toontrack.com/product/superior-drummer-3/, https://www.toontrack.com/product/ezdrummer-3/, https://www.toontrack.com/product/ezbass/.
- IK Multimedia MODO BASS 2 and MODO DRUM: https://www.ikmultimedia.com/products/modobass2/, https://www.ikmultimedia.com/products/mododrum/.
- Neural DSP downloads: https://neuraldsp.com/downloads — Archetype: Plini X.
- Line 6 Helix Native: https://line6.com/helix/helixnative.html.

## Selection limits

The set prioritizes distinct current, named plug-ins from the supplied list. It omits known existing catalog entries, bundles, library-only products, unverified aliases, and items for which this bounded pass did not establish a sufficiently exact product identity. It does not try to infer a plugin’s maker from a bundle or a product-family name.


# Prism library catalog expansion — source notes

Reviewed 2026-10-06. This is a representative set of 150 additional named sample or Kontakt instrument products; it is not a popularity ranking. Product editions are kept distinct when the maker sells them as distinct installed products. Generic platforms, bundles, expansion packs, presets, and effects were excluded. All records are offline-only (`networkEnabled: false`). Each `page` and `endpoint` is an official maker product page and each `sourceFact` is an original, short category paraphrase. The official pages are cited per record in `Sources/SimplifyCore/Resources/product-tag-catalog-v2.json`.

Source collections and verification method:

- [Spitfire Audio product collection](https://www.spitfireaudio.com/collections/all): selected standalone instrument and library products. Verified each title against the official Shopify product response at its exact `/products/<slug>.js` URL; the stored URL is the corresponding public product page. The selected titles include BBC Symphony Orchestra Discover, Spitfire Solo Strings, Eric Whitacre Choir, Abbey Road series, Hans Zimmer Percussion, and Originals.
- [Native Instruments instrument catalog](https://www.native-instruments.com/collections/instruments): verified exact product title and catalog instrument tags in each official product response. Includes Session Guitarist, Session Strings, Studio Drummer, The Grandeur, Spotlight Collection, and Action Strings. The broader Spotlight products are tagged conservatively rather than asserting every contained patch.
- [Heavyocity product catalog](https://heavyocity.com/products): verified titles and descriptions at exact official product responses. Includes Damage 2, NOVO, FORZO, VENTO, Symphonic Destruction, Vocalise, and keyboard/texture instruments. Excluded catalog items labeled Collections.
- [8Dio instrument catalog](https://8dio.com/collections/instruments): verified titles and product descriptions at exact official product responses. Includes Adagio Basses, anthology strings, solo brass, and choirs. Excluded product titles labeled Bundle.
- [Audio Imperia shop](https://www.audioimperia.com/shop/): selected direct official `/product/` pages; verified each page returned a product title. Includes Nucleus, Cerberus, Dolce, Fluid Brass, Fluid Woods, Klavier, and distinct Lite editions. Product descriptions substantiate the instrument family tags.
- [Output instrument catalog](https://legacy-rest.output.com/products) and [Output Kontakt support article](https://support.output.com/en/articles/10297787-kontakt-and-why-you-need-it): Signal, Exhale, Analog Strings, Substance, and REV are named Kontakt instruments; their individual official `output.com/products/` pages were verified. Their metadata reflects musical purpose, not every acoustic source used in synthesis. Output Movement and other effects were excluded.

No source is used as evidence of product popularity, installed status, license ownership, individual patch inventory, or historical usage. No account or sample payload was accessed. The established 50 library records remain separate and were excluded by ID and maker/name during generation.
