import Foundation

/// Initial reviewed coverage, verified 2026-09-26. A matching product page never proves installation or use.
/// See docs/research/product-tag-sources.md for extraction and review constraints.
public enum ProductTagSources {
    public static let all: [ProductTagSource] = [
        ProductTagSource(id: "spitfire-symphony-orchestra", kind: .library,
            names: ["Spitfire Symphony Orchestra"], makers: ["Spitfire Audio", "Spitfire"], bundlePrefix: nil,
            endpoint: URL(string: "https://www.spitfireaudio.com/products/spitfire-symphony-orchestra.json")!,
            page: URL(string: "https://www.spitfireaudio.com/products/spitfire-symphony-orchestra")!, format: .shopify,
            remoteName: "Spitfire Symphony Orchestra", descriptionDigest: "da668563981f10ffe91c65d72d4b5d5bc6b73179ec0bd45270de8841bc1208dc",
            metadata: MusicalMetadata(fields: ["instrument": ["strings", "brass", "woodwinds", "harp", "piano", "percussion"], "ensemble": ["ensemble"]])),
        ProductTagSource(id: "bbc-symphony-orchestra-core", kind: .library,
            names: ["BBC Symphony Orchestra Core"], makers: ["Spitfire Audio", "Spitfire"], bundlePrefix: nil,
            endpoint: URL(string: "https://www.spitfireaudio.com/products/bbc-symphony-orchestra-core.json")!,
            page: URL(string: "https://www.spitfireaudio.com/products/bbc-symphony-orchestra-core")!, format: .shopify,
            remoteName: "BBC Symphony Orchestra Core", descriptionDigest: "1f109582d7a2bb4afb09ab21690f42bce4d09365a62d9b696c3ca6b3ae4f2cef",
            metadata: MusicalMetadata(fields: ["instrument": ["strings", "brass", "woodwinds", "percussion"]])),
        ProductTagSource(id: "berlin-strings", kind: .library,
            names: ["Berlin Strings"], makers: ["Orchestral Tools"], bundlePrefix: nil,
            endpoint: URL(string: "https://www.orchestraltools.com/berlin-strings")!,
            page: URL(string: "https://www.orchestraltools.com/berlin-strings")!, format: .productJSONLD,
            remoteName: "Berlin Strings - Flagship string ensembles", descriptionDigest: "6bbca8f456ef66919aca49e99bf1f2a8f6285e1dc9831460f34a388785d11666",
            metadata: MusicalMetadata(fields: ["instrument": ["strings"], "ensemble": ["ensemble"], "technique": ["legato"]])),
        ProductTagSource(id: "cinematic-studio-strings", kind: .library,
            names: ["Cinematic Studio Strings"], makers: ["Cinematic Studio Series", "Cinematic Strings"], bundlePrefix: nil,
            endpoint: URL(string: "https://cinematicstudioseries.com/wp-json/wp/v2/pages/68?_fields=id,slug,link,title,excerpt")!,
            page: URL(string: "https://cinematicstudioseries.com/strings/")!, format: .wordpress,
            remoteName: "Cinematic Studio Strings", descriptionDigest: "62908892e9b97ad9c1f7a619c81be33ec42809bef670975e19124e8e46249e40",
            metadata: MusicalMetadata(fields: ["instrument": ["strings"]])),
        ProductTagSource(id: "cinematic-strings-2", kind: .library,
            names: ["Cinematic Strings 2"], makers: ["Cinematic Strings", "Cinematic Studio Series"], bundlePrefix: nil,
            endpoint: URL(string: "https://cinematicstudioseries.com/wp-json/wp/v2/pages/900?_fields=id,slug,link,title,excerpt")!,
            page: URL(string: "https://cinematicstudioseries.com/cs2/")!, format: .wordpress,
            remoteName: "Cinematic Strings 2", descriptionDigest: "d2821fd05a9a4a8e991fe630035490e5e79aea6a70b8dbde3b734f613153c289",
            metadata: MusicalMetadata(fields: ["instrument": ["strings"], "character": ["warm"]])),
        ProductTagSource(id: "fabfilter-pro-q-4", kind: .plugin,
            names: ["FabFilter Pro-Q 4", "Pro-Q 4"], makers: [], bundlePrefix: "com.fabfilter",
            endpoint: URL(string: "https://www.fabfilter.com/products/pro-q-4-equalizer-plug-in")!,
            page: URL(string: "https://www.fabfilter.com/products/pro-q-4-equalizer-plug-in")!, format: .metaDescription,
            remoteName: "FabFilter Pro-Q 4 - Equalizer Plug-In", descriptionDigest: "bb10fee1812b2adb95439d7f16f1b2f8db59f36be5145164043370aed38ebf53",
            metadata: MusicalMetadata(fields: ["function": ["equalizer", "eq"]])),
    ]
}
