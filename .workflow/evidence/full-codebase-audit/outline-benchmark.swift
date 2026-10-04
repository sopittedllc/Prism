import Foundation
import SimplifyCore
import SimplifyCatalog
@main struct AuditBenchmark {
 @MainActor static func main() throws {
  for count in [1000, 10000, 100000] {
   let objects = (0..<count).map { i -> [String: Any] in
    ["kind":"sample", "path":"/AuditSamples/Pack \(i / 100)/\(i % 10 == 0 ? "Accordion" : "Drum") \(i).wav", "name":"\(i % 10 == 0 ? "Accordion" : "Drum") \(i)", "format":"wav", "logicalBytes":1000+i,"classification":"Audio file"]
   }
   let assets = try JSONDecoder().decode([Asset].self, from: JSONSerialization.data(withJSONObject: objects))
   let start = Date()
   let outline = CatalogOutline.build(assets: assets, category: .sample, sampleRoots: [URL(fileURLWithPath:"/AuditSamples")])
   let build = Date().timeIntervalSince(start)
   var durations:[Double]=[];var hits=0
   for _ in 0..<5 {
    let started=Date();let found=outline.filtered(query:"Accordion");hits=found.roots.count;durations.append(Date().timeIntervalSince(started)*1000)
   }
   let row:[String:Any] = ["assets":count,"build_seconds":build,"filter_ms":durations,"matches":hits,"scope":"release CatalogOutline build/filter on main actor; no filesystem, AppKit reload or DB; 5 repeated identical queries; not p95"]
   print(String(decoding:try JSONSerialization.data(withJSONObject:row,options:[.sortedKeys]),as:UTF8.self))
  }
 }
}
