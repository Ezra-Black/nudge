import Foundation

struct GuideStep: Codable {
    var title: String
    var explanation: String
    var target: String
    var action: Bool
    var evidence: String
    /// Tour steps arrive in batches. A step that isn't ready still has its target but no explanation yet.
    var ready = true
    var area = ""
}
/// One control's explanation from a tour batch. `target` is the item's number within its batch.
struct ExplainedStep: Codable {
    var target: String
    var title: String
    var explanation: String
}
struct GuidePlan: Codable {
    var title: String
    var introduction: String
    var conclusion: String
    var steps: [GuideStep]
    var continues: Bool
}
struct GuideState: Codable {
    var status: String
    var plan: GuidePlan?
    var index: Int?
    var bounds: UnitRect?
    var goal: String?
    var target_source: String?
    var step: GuideStep? {
        guard let plan, let index, plan.steps.indices.contains(index) else { return nil }
        return plan.steps[index]
    }
}
struct Preparation: Decodable {
    var cached: Bool
    var prompt: String?
    var request: String?
    var state: GuideState?
    var batches: [String]?
}
