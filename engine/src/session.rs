//! The engine's state between commands, and the commands themselves.
//!
//! `prepare` reads an observation, builds the prompts and leaves a pending interpretation. `install` turns the
//! model's plan into the active guide. For a tour, `explain` then fills in its steps a batch at a time. Finished
//! tours are kept in a small in-memory cache, so opening the same tour again skips the model.

use std::{
    collections::{HashMap, HashSet},
    time::{Duration, Instant},
};

use serde::Deserialize;
use serde_json::{json, Value};

use crate::{
    clipped,
    geometry::{mostly_inside, union, within, Rect},
    model::{Element, Explained, Observation, Plan, Step},
    prompt::{batch_prompt, fallback, goal_prompt, item_line, overview_prompt},
    select::{is_text, kind, select},
    tour::{area_stops, opening, plural, tour_queue, Item},
    BATCH, TOUR_LIMIT,
};

/// Share of the original window's controls a read must still have to count as the same screen.
const SAME_SCREEN: f64 = 0.60;

/// Words that only say what kind of thing a step is. A title made of nothing else is not used.
#[rustfmt::skip]
const GENERIC_WORDS: &[&str] = &[
    "a", "an", "the", "this", "of", "picture", "image", "photo", "photograph", "text", "icon", "graphic", "block",
    "paragraph", "heading", "button", "link",
];

/// The active guide.
///
/// `clusters` maps a grouped step's target to the controls it highlights together. `fixed` holds where each block of
/// text in a chosen area was read; that text came from a picture, so later reads without one can't find it again.
/// `key` identifies the tour in the cache: window structure, goal and scope.
/// `latest` is the most recent read of the same window, so moving between steps uses current positions
/// without reading the window again.
struct Session {
    plan: Plan,
    original: Observation,
    latest: Option<Observation>,
    index: usize,
    goal: String,
    /// The `prepare` request a tour's `explain` calls must match. Empty for goal guides and cached tours.
    request: String,
    /// Step indices, one list per `explain` batch.
    batches: Vec<Vec<usize>>,
    /// A description of each step from what was observed, for steps the model doesn't explain.
    fallbacks: Vec<String>,
    clusters: HashMap<String, Vec<Element>>,
    fixed: HashMap<String, Rect>,
    key: String,
}

impl Session {
    /// A guide at its first step, not yet tied to a request or the cache.
    fn new(plan: Plan, original: Observation, goal: String) -> Self {
        Session {
            plan,
            original,
            latest: None,
            index: 0,
            goal,
            request: String::new(),
            batches: Vec::new(),
            fallbacks: Vec::new(),
            clusters: HashMap::new(),
            fixed: HashMap::new(),
            key: String::new(),
        }
    }
}

/// A prompt waiting for the model's plan. Only an `install` with the same `request` can answer it.
struct Pending {
    request: String,
    observation: Observation,
    /// The items the model was shown, by number.
    chosen: Vec<Element>,
    goal: String,
    /// A tour's stops, in order. Empty for a goal.
    queue: Vec<Item>,
    fixed: HashMap<String, Rect>,
    key: String,
}

/// A finished tour, kept so the same tour can be shown again without the model.
struct Cached {
    plan: Plan,
    clusters: HashMap<String, Vec<Element>>,
    fixed: HashMap<String, Rect>,
    at: Instant,
}

/// The guide engine: at most one pending interpretation, at most one active guide, and the tour cache.
///
/// Feed it protocol lines with [`handle_line`](crate::handle_line). It keeps no state outside memory.
#[derive(Default)]
pub struct Engine {
    pending: Option<Pending>,
    session: Option<Session>,
    cache: HashMap<String, Cached>,
}

/// Reads `v[key]` as a `T`. The error names the field.
fn parse<T: for<'a> Deserialize<'a>>(v: &Value, key: &str) -> Result<T, String> {
    serde_json::from_value(v[key].clone()).map_err(|e| format!("Invalid {key}: {e}"))
}

/// The cache key for a tour: app, window title, `goal` (which also carries the tour's scope and options), and the
/// window's structure as every element's id, role and label.
fn signature(o: &Observation, goal: &str) -> String {
    let mut keys: Vec<_> = o
        .elements
        .iter()
        .map(|e| format!("{}:{}:{}", e.id, e.role, e.label))
        .collect();
    keys.sort();
    format!("{}|{}|{}|{}", o.bundle, o.window, goal, keys.join("|"))
}

/// Finds `anchor` again in a later read of the window.
fn resolve<'a>(anchor: &Element, o: &'a Observation) -> Option<&'a Element> {
    let candidates: Vec<_> = o
        .elements
        .iter()
        .filter(|e| e.role == anchor.role && e.label == anchor.label && e.source == anchor.source && e.bounds.valid())
        .collect();
    // A unique label+role remains usable after reordering. Repeated controls need their stable path.
    if candidates.len() == 1 {
        return Some(candidates[0]);
    }
    let exact: Vec<_> = candidates.into_iter().filter(|e| e.id == anchor.id).collect();
    if exact.len() == 1 {
        Some(exact[0])
    } else {
        None
    }
}

/// Share of the original window's controls still present. Plain text and OCR are ignored so
/// scrolling a page, or a tracking read without OCR, doesn't look like a new screen.
fn structure_overlap(original: &Observation, now: &Observation) -> f64 {
    let key = |e: &Element| (e.role.clone(), e.label.clone());
    // Pictures found in a screenshot aren't in later reads either.
    let stable = |e: &&Element| !is_text(e) && e.source != "vision";
    let mut old: HashSet<_> = original.elements.iter().filter(stable).map(key).collect();
    let mut current: HashSet<_> = now.elements.iter().filter(stable).map(key).collect();
    if old.is_empty() {
        old = original.elements.iter().map(key).collect();
        current = now.elements.iter().map(key).collect();
    }
    old.intersection(&current).count() as f64 / old.len().max(1) as f64
}

impl Engine {
    /// Runs one protocol command and returns its `data`, or the error message for the client.
    pub(crate) fn dispatch(&mut self, v: &Value) -> Result<Value, String> {
        if v["version"] != 1 {
            return Err("Unsupported protocol version".into());
        }
        match v["command"].as_str().unwrap_or("") {
            "hello" => Ok(json!({"protocol": 1, "engine": "Nudge", "network": false})),
            "prepare" => self.prepare(v),
            "install" => self.install(v),
            "explain" => self.explain(v),
            "observe" => self.observe(v),
            "next" => {
                if let Some(s) = &mut self.session {
                    s.index = (s.index + 1).min(s.plan.steps.len());
                }
                Ok(self.state(None))
            }
            "back" => {
                if let Some(s) = &mut self.session {
                    s.index = s.index.saturating_sub(1);
                }
                Ok(self.state(None))
            }
            "goto" => {
                let index = v["index"].as_u64().ok_or("Missing step index")? as usize;
                if let Some(s) = &mut self.session {
                    s.index = index.min(s.plan.steps.len());
                }
                Ok(self.state(None))
            }
            "replay" => {
                if let Some(s) = &mut self.session {
                    s.index = 0;
                }
                Ok(self.state(None))
            }
            "clear" => {
                self.session = None;
                self.pending = None;
                self.cache.clear();
                Ok(json!({"status": "idle"}))
            }
            "cancel" => {
                self.pending = None;
                Ok(json!({"status": "cancelled"}))
            }
            _ => Err("Unknown command".into()),
        }
    }

    /// Reads a fresh observation and builds the prompts: a tour's overview and batches when there's no goal,
    /// otherwise the next step toward the goal. A tour already in the cache starts straight away.
    fn prepare(&mut self, v: &Value) -> Result<Value, String> {
        let mut o: Observation = parse(v, "observation")?;
        o.elements.retain(|e| e.bounds.valid() && !e.label.trim().is_empty());
        o.elements.truncate(600);
        if o.elements.is_empty() {
            return Err("I couldn’t read any labeled controls. Try a website or a standard Mac app.".into());
        }
        let goal = clipped(v["goal"].as_str().unwrap_or(""), 300);
        let progress = clipped(v["progress"].as_str().unwrap_or(""), 300);
        // In a browser, a tour covers either the web page ("web") or the browser around it ("app").
        // An area the person dragged out, as fractions of the observed frame. Only what's mostly inside it is explained.
        let region: Option<Rect> = if goal.is_empty() {
            serde_json::from_value(v["region"].clone()).ok()
        } else {
            None
        };
        let scope = if region.is_some() {
            "area".to_string()
        } else if goal.is_empty() {
            v["scope"].as_str().unwrap_or("all").to_string()
        } else {
            "all".to_string()
        };
        let limit = v["limit"]
            .as_u64()
            .map(|n| (n as usize).clamp(4, 80))
            .unwrap_or(TOUR_LIMIT);
        let grouping = v["group"].as_bool().unwrap_or(true);
        let area = region
            .as_ref()
            .map(|r| format!("{:.3},{:.3},{:.3},{:.3}", r.x, r.y, r.width, r.height))
            .unwrap_or_default();
        let key = signature(&o, &format!("{goal}|{scope}|{area}|{limit}|{grouping}"));
        self.cache.retain(|_, c| c.at.elapsed() < Duration::from_secs(1200));
        if progress.is_empty() {
            if let Some(c) = self.cache.get(&key) {
                let mut session = Session::new(c.plan.clone(), o, goal);
                session.clusters = c.clusters.clone();
                session.fixed = c.fixed.clone();
                session.key = key;
                self.session = Some(session);
                return Ok(json!({"cached": true, "state": self.state(None)}));
            }
        }
        let focus: Vec<Element> = match scope.as_str() {
            // Only what is mostly inside the box, with positions measured within the box rather than the window.
            "area" => {
                let r = region.clone().ok_or("An area guide needs the area's region.")?;
                o.elements
                    .iter()
                    .filter(|e| mostly_inside(&e.bounds, &r))
                    .cloned()
                    .map(|mut e| {
                        e.bounds = within(&e.bounds, &r);
                        e
                    })
                    .collect()
            }
            "web" => o
                .elements
                .iter()
                .filter(|e| e.web || e.source == "ocr")
                .cloned()
                .collect(),
            "app" => o
                .elements
                .iter()
                .filter(|e| !e.web && e.source != "ocr")
                .cloned()
                .collect(),
            _ => o.elements.clone(),
        };
        if focus.is_empty() {
            return Err(match scope.as_str() {
                "web" => "I couldn’t read this page’s content yet. Let it finish loading, then try again.",
                "area" => {
                    "I couldn’t find anything to explain in that area. Try a larger area, or allow Screen Recording \
                     for Nudge in System Settings so it can read text and pictures."
                }
                _ => "I couldn’t read any labeled controls. Try a website or a standard Mac app.",
            }
            .into());
        }
        let chosen = select(&focus);
        // Model sees compact numeric references. Install maps only to verified observed anchors.
        let lines: Vec<_> = chosen.iter().enumerate().map(|(i, e)| item_line(i, e, 0)).collect();
        let request = v["request"].as_str().unwrap_or("").to_string();
        if goal.is_empty() {
            // A tour is an overview of the whole window, then every control explained in small batches.
            let mut queue = tour_queue(&focus, limit, grouping);
            // After the area's controls, its text: each block highlighted and explained in turn.
            let (stops, fixed) = match region.as_ref().filter(|_| scope == "area") {
                Some(r) => area_stops(&o.elements, r),
                None => (Vec::new(), HashMap::new()),
            };
            queue.extend(stops);
            let prompt = overview_prompt(&o, &scope, &lines);
            let batches: Vec<String> = queue
                .chunks(BATCH)
                .map(|items| batch_prompt(&o, items, scope == "area"))
                .collect();
            self.pending = Some(Pending {
                request: request.clone(),
                observation: o,
                chosen,
                goal,
                queue,
                fixed,
                key,
            });
            return Ok(json!({"cached": false, "prompt": prompt, "batches": batches, "request": request}));
        }
        let prompt = goal_prompt(&o, &goal, &progress, &lines);
        self.pending = Some(Pending {
            request: request.clone(),
            observation: o,
            chosen,
            goal,
            queue: Vec::new(),
            fixed: HashMap::new(),
            key,
        });
        Ok(json!({"cached": false, "prompt": prompt, "request": request}))
    }

    /// Takes the model's plan for the pending prompt, if it answers the latest `prepare`.
    fn install(&mut self, v: &Value) -> Result<Value, String> {
        let request = v["request"].as_str().unwrap_or("");
        let p = self.pending.take().ok_or("No pending interpretation")?;
        if p.request != request {
            self.pending = Some(p);
            return Err("Stale interpretation discarded".into());
        }
        let mut plan: Plan = parse(v, "plan")?;
        plan.title = clipped(&plan.title, 100);
        plan.introduction = clipped(&plan.introduction, 400);
        plan.conclusion = clipped(&plan.conclusion, 300);
        if p.goal.is_empty() {
            return Ok(self.install_tour(p, plan));
        }
        let proposed = plan.steps.len();
        let mut used = HashSet::new();
        // Drop steps that point at unverifiable or repeated controls rather than discarding the whole guide.
        plan.steps.retain_mut(|s| {
            let Some(e) = s.target.trim().parse::<usize>().ok().and_then(|n| p.chosen.get(n)) else {
                return false;
            };
            if !used.insert(e.id.clone()) {
                return false;
            }
            s.target = e.id.clone();
            s.area = e.context.clone();
            s.ready = true;
            s.title = clipped(s.title.trim(), 80);
            s.explanation = clipped(s.explanation.trim(), 420);
            s.evidence = clipped(s.evidence.trim(), 200);
            !s.title.is_empty() && !s.explanation.is_empty()
        });
        if proposed > 0 && plan.steps.is_empty() {
            return Err("The guide referred to controls I couldn’t verify. Please try again.".into());
        }
        plan.steps.truncate(1);
        if plan.steps.is_empty() {
            plan.continues = false;
        }
        self.session = Some(Session::new(plan, p.observation, p.goal));
        Ok(self.state(None))
    }

    /// Tour: the model wrote the overview. Steps start as placeholders that `explain` fills in.
    fn install_tour(&mut self, p: Pending, mut plan: Plan) -> Value {
        plan.continues = false;
        plan.steps = p
            .queue
            .iter()
            .map(|it| {
                let e = &it.element;
                let title = if e.role == "AXTextBlock" {
                    opening(&e.label)
                } else if it.members.len() > 1 {
                    format!("{} {}", it.members.len(), plural(kind(&e.role)))
                } else {
                    clipped(&e.label, 80)
                };
                Step {
                    title,
                    explanation: String::new(),
                    target: e.id.clone(),
                    action: false,
                    evidence: format!("{} {}", kind(&e.role), clipped(&e.label, 80)),
                    ready: false,
                    area: e.context.clone(),
                }
            })
            .collect();
        let mut session = Session::new(plan, p.observation, p.goal);
        session.request = p.request;
        session.key = p.key;
        session.fixed = p.fixed;
        session.clusters = p
            .queue
            .iter()
            .filter(|it| it.members.len() > 1)
            .map(|it| (it.element.id.clone(), it.members.clone()))
            .collect();
        session.fallbacks = p.queue.iter().map(fallback).collect();
        session.batches = (0..p.queue.len())
            .collect::<Vec<_>>()
            .chunks(BATCH)
            .map(|c| c.to_vec())
            .collect();
        if session.plan.steps.is_empty() {
            self.remember(&session);
        }
        self.session = Some(session);
        self.state(None)
    }

    /// Fills one batch of tour steps with the model's explanations. Steps it skipped get their fallback.
    fn explain(&mut self, v: &Value) -> Result<Value, String> {
        let request = v["request"].as_str().unwrap_or("");
        let batch = v["batch"].as_u64().ok_or("Missing batch")? as usize;
        let proposed: Vec<Explained> = parse(v, "steps").unwrap_or_default();
        let s = self.session.as_mut().ok_or("No guide is active")?;
        if request.is_empty() || s.request != request {
            return Err("Stale explanation discarded".into());
        }
        let members = s.batches.get(batch).cloned().ok_or("Unknown batch")?;
        let mut used = HashSet::new();
        // Items are numbered from 1. Small models sometimes count from 0, or drop the numbers but keep the order.
        let zero_based = proposed.iter().any(|e| e.target.trim() == "0");
        let in_order = proposed.len() == members.len();
        for (position, e) in proposed.into_iter().enumerate() {
            let numbered = e
                .target
                .trim()
                .trim_start_matches('#')
                .parse::<usize>()
                .ok()
                .and_then(|n| n.checked_sub(if zero_based { 0 } else { 1 }));
            let slot = match numbered {
                Some(n) if n < members.len() => Some(n),
                _ if in_order => Some(position),
                _ => None,
            };
            let Some(&i) = slot.and_then(|n| members.get(n)) else {
                continue;
            };
            let text = clipped(e.explanation.trim(), 420);
            if text.is_empty() || !used.insert(i) {
                continue;
            }
            let step = &mut s.plan.steps[i];
            let title = clipped(e.title.trim(), 80);
            // "Picture" or "Text" says less than the heading the step already has.
            let generic = title
                .to_lowercase()
                .split(|c: char| !c.is_alphanumeric())
                .filter(|w| !w.is_empty())
                .all(|w| GENERIC_WORDS.contains(&w));
            if !generic {
                step.title = title;
            }
            step.explanation = text;
            step.ready = true;
        }
        // Anything the model skipped still gets a truthful description from what was observed.
        for &i in &members {
            let step = &mut s.plan.steps[i];
            if !step.ready {
                step.explanation = s.fallbacks[i].clone();
                step.ready = true;
            }
        }
        if s.plan.steps.iter().all(|step| step.ready) {
            let key = s.key.clone();
            let plan = s.plan.clone();
            let clusters = s.clusters.clone();
            let fixed = s.fixed.clone();
            self.store(key, plan, clusters, fixed);
        }
        Ok(self.state(None))
    }

    /// Checks the current step against a fresh read. A read of the same window becomes the latest one.
    fn observe(&mut self, v: &Value) -> Result<Value, String> {
        let o: Observation = parse(v, "observation")?;
        let state = self.state(Some(&o));
        if let Some(s) = &mut self.session {
            if o.bundle == s.original.bundle && o.window_id == s.original.window_id {
                s.latest = Some(o);
            }
        }
        Ok(state)
    }

    /// Caches a finished tour. Goal guides aren't cached.
    fn remember(&mut self, s: &Session) {
        if s.goal.is_empty() {
            self.store(s.key.clone(), s.plan.clone(), s.clusters.clone(), s.fixed.clone());
        }
    }

    /// Adds a tour to the cache, which holds at most 12: when full, it starts over.
    fn store(
        &mut self,
        key: String,
        plan: Plan,
        clusters: HashMap<String, Vec<Element>>,
        fixed: HashMap<String, Rect>,
    ) {
        if self.cache.len() >= 12 {
            self.cache.clear();
        }
        self.cache.insert(
            key,
            Cached {
                plan,
                clusters,
                fixed,
                at: Instant::now(),
            },
        );
    }

    /// The guide as the client sees it: the plan, the current step, and where its target is.
    ///
    /// Positions come from `observation` when given, else the latest read of the window, else the original one.
    /// `status` is `idle` without a guide, `complete` past the last step, `changed` when the window is another one
    /// or its structure changed, `missing` when the target can't be found, and `step` otherwise.
    fn state(&self, observation: Option<&Observation>) -> Value {
        let Some(s) = &self.session else {
            return json!({"status": "idle"});
        };
        let mut status = if s.index >= s.plan.steps.len() {
            "complete"
        } else {
            "step"
        };
        let mut bounds = None;
        let mut source = None;
        if let Some(step) = s.plan.steps.get(s.index) {
            let o = observation.or(s.latest.as_ref()).unwrap_or(&s.original);
            if o.bundle != s.original.bundle || o.window_id != s.original.window_id || o.window != s.original.window {
                status = "changed";
            } else if let Some(r) = s.fixed.get(&step.target) {
                // Text and pictures found in a screenshot of the area stay where they were found, like the area itself.
                source = Some("area".to_string());
                bounds = Some(r.clone());
                if structure_overlap(&s.original, o) < SAME_SCREEN {
                    status = "changed";
                    bounds = None;
                }
            } else if let Some(members) = s.clusters.get(&step.target) {
                // A group stays highlighted while most of its controls can still be found.
                source = Some("ax".to_string());
                let found: Vec<&Element> = members.iter().filter_map(|m| resolve(m, o)).collect();
                if !found.is_empty() && found.len() * 2 >= members.len() {
                    bounds = Some(union(&found));
                } else {
                    status = "missing";
                }
                if structure_overlap(&s.original, o) < SAME_SCREEN {
                    status = "changed";
                    bounds = None;
                }
            } else if let Some(anchor) = s.original.elements.iter().find(|e| e.id == step.target) {
                source = Some(anchor.source.clone());
                if let Some(current) = resolve(anchor, o) {
                    bounds = Some(current.bounds.clone());
                } else {
                    status = "missing";
                }
                if structure_overlap(&s.original, o) < SAME_SCREEN {
                    status = "changed";
                    bounds = None;
                }
            } else {
                status = "missing";
            }
        }
        json!({"status": status, "plan": s.plan, "index": s.index, "bounds": bounds, "goal": s.goal, "target_source": source})
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::tests::element;

    fn observation(elements: Vec<Element>) -> Observation {
        Observation {
            app: "App".to_string(),
            bundle: "com.example.app".to_string(),
            window: "Window".to_string(),
            window_id: 1,
            elements,
            page: String::new(),
            scene: String::new(),
        }
    }

    fn with_source(mut e: Element, source: &str) -> Element {
        e.source = source.to_string();
        e
    }

    fn controls() -> Vec<Element> {
        ["Back", "Forward", "Share", "Save"]
            .iter()
            .enumerate()
            .map(|(i, label)| element(label, "AXButton", 0.1 * i as f64, 0.0, 0.05, 0.05))
            .collect()
    }

    #[test]
    fn structure_overlap_ignores_ocr_text_and_pictures() {
        let mut before = controls();
        before.push(with_source(
            element("Welcome", "visible text", 0.1, 0.5, 0.3, 0.05),
            "ocr",
        ));
        before.push(element("Signed in", "AXStaticText", 0.1, 0.6, 0.3, 0.05));
        before.push(with_source(element("Photo", "picture", 0.5, 0.5, 0.3, 0.3), "vision"));
        // A later read without OCR or pictures, and different text: the same screen.
        let mut after = controls();
        after.push(element("Signed out", "AXStaticText", 0.1, 0.6, 0.3, 0.05));
        assert_eq!(
            structure_overlap(&observation(before.clone()), &observation(after)),
            1.0
        );
        // Half the controls gone: half the structure left.
        let half: Vec<Element> = controls().into_iter().take(2).collect();
        assert_eq!(structure_overlap(&observation(before), &observation(half)), 0.5);
    }

    #[test]
    fn structure_overlap_uses_everything_when_there_are_no_controls() {
        let text = |label: &str| with_source(element(label, "visible text", 0.1, 0.1, 0.3, 0.05), "ocr");
        let before = observation(vec![text("One"), text("Two")]);
        assert_eq!(structure_overlap(&before, &observation(vec![text("One")])), 0.5);
        assert_eq!(
            structure_overlap(&observation(Vec::new()), &observation(Vec::new())),
            0.0
        );
    }

    #[test]
    fn resolve_needs_an_exact_id_for_repeated_labels() {
        let reply = element("Reply", "AXButton", 0.1, 0.1, 0.1, 0.05);
        let mut moved = reply.clone();
        moved.id = "row 2/Reply".to_string();
        moved.bounds.y = 0.5;
        // Unique label and role: found after its id changed.
        let found = resolve(&reply, &observation(vec![moved.clone()])).map(|e| e.bounds.y);
        assert_eq!(found, Some(0.5));
        // Two of them: only the same id will do.
        let mut other = moved.clone();
        other.id = "row 3/Reply".to_string();
        assert!(resolve(&reply, &observation(vec![moved.clone(), other.clone()])).is_none());
        let found = resolve(&reply, &observation(vec![other, reply.clone(), moved])).map(|e| e.id.clone());
        assert_eq!(found.as_deref(), Some("Reply"));
        // Found by OCR is not the same as found through accessibility.
        let ocr = with_source(reply.clone(), "ocr");
        assert!(resolve(&reply, &observation(vec![ocr])).is_none());
    }

    #[test]
    fn signature_ignores_element_order() {
        let mut reversed = controls();
        reversed.reverse();
        assert_eq!(
            signature(&observation(controls()), "g"),
            signature(&observation(reversed), "g")
        );
        assert_ne!(
            signature(&observation(controls()), "g"),
            signature(&observation(controls()), "h")
        );
    }

    #[test]
    fn cache_holds_at_most_twelve_tours() {
        let mut engine = Engine::default();
        let plan = Plan {
            title: String::new(),
            introduction: String::new(),
            conclusion: String::new(),
            steps: Vec::new(),
            continues: false,
        };
        for n in 0..12 {
            engine.store(n.to_string(), plan.clone(), HashMap::new(), HashMap::new());
        }
        assert_eq!(engine.cache.len(), 12);
        engine.store("13".to_string(), plan, HashMap::new(), HashMap::new());
        assert_eq!(engine.cache.len(), 1);
    }

    #[test]
    fn cached_tours_expire_after_twenty_minutes() {
        let prepare = json!({
            "version": 1, "command": "prepare", "request": "r",
            "observation": {"app": "App", "bundle": "b", "window": "w", "window_id": 1, "elements": [
                {"id": "t", "label": "Just text", "role": "AXStaticText", "source": "ax",
                 "bounds": {"x": 0.1, "y": 0.1, "width": 0.2, "height": 0.05}}
            ]}
        });
        let install = json!({"version": 1, "command": "install", "request": "r",
            "plan": {"title": "t", "introduction": "i", "conclusion": "c", "steps": []}});
        let mut engine = Engine::default();
        assert_eq!(engine.dispatch(&prepare).unwrap()["cached"], false);
        // A tour with no controls is finished as soon as it's installed.
        engine.dispatch(&install).unwrap();
        assert_eq!(engine.dispatch(&prepare).unwrap()["cached"], true);
        let Some(long_ago) = Instant::now().checked_sub(Duration::from_secs(1201)) else {
            return;
        };
        for c in engine.cache.values_mut() {
            c.at = long_ago;
        }
        assert_eq!(engine.dispatch(&prepare).unwrap()["cached"], false);
    }
}
