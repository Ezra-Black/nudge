//! The data that crosses the wire: what the client observed, and the plans the model writes.
//!
//! Field names are part of protocol v1 (see `docs/PROTOCOL.md`); renaming one breaks the Swift client.

use serde::{Deserialize, Serialize};

use crate::geometry::Rect;

/// One thing the client read in the window: a control, an area, a line of text, a picture.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub(crate) struct Element {
    /// Unique within one observation, and stable across reads of the same window where possible.
    pub(crate) id: String,
    pub(crate) label: String,
    /// An accessibility role such as `AXButton`, or `picture` for a picture found in a screenshot.
    pub(crate) role: String,
    pub(crate) bounds: Rect,
    /// Where it was found: `ax` (accessibility), `ocr` (text in a screenshot) or `vision` (a picture).
    #[serde(default)]
    pub(crate) source: String,
    /// The named part of the window it sits in, such as `Toolbar` or `Sidebar`.
    #[serde(default)]
    pub(crate) context: String,
    /// A link's destination, a button's `tip: …`, a checkbox's `on`/`off`, a picture's `looks like: …`.
    #[serde(default)]
    pub(crate) detail: String,
    /// Part of the web page rather than the browser around it.
    #[serde(default)]
    pub(crate) web: bool,
}

/// One read of a window.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub(crate) struct Observation {
    pub(crate) app: String,
    pub(crate) bundle: String,
    pub(crate) window: String,
    pub(crate) window_id: u32,
    pub(crate) elements: Vec<Element>,
    /// The web address without query or fragment, in a browser.
    #[serde(default)]
    pub(crate) page: String,
    /// What a picture of a chosen area looks like, when the client could tell.
    #[serde(default)]
    pub(crate) scene: String,
}

/// A step the model wrote is ready unless it says otherwise.
fn yes() -> bool {
    true
}

/// One stop in a guide.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub(crate) struct Step {
    pub(crate) title: String,
    pub(crate) explanation: String,
    /// The model's item number until `install`, then the observed element's id.
    pub(crate) target: String,
    /// Whether the person is asked to do something rather than just read.
    #[serde(default)]
    pub(crate) action: bool,
    /// What the model saw that supports the step.
    #[serde(default)]
    pub(crate) evidence: String,
    /// False while a tour stop waits for `explain`.
    #[serde(default = "yes")]
    pub(crate) ready: bool,
    /// The part of the window the target sits in.
    #[serde(default)]
    pub(crate) area: String,
}

/// The model's explanation of one item in a tour batch. `target` is the item's number within the batch.
#[derive(Debug, Default, Deserialize)]
pub(crate) struct Explained {
    #[serde(default)]
    pub(crate) target: String,
    #[serde(default)]
    pub(crate) title: String,
    #[serde(default)]
    pub(crate) explanation: String,
}

/// A guide: the model's overview and its steps. `continues` asks for another plan once the step is done.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub(crate) struct Plan {
    pub(crate) title: String,
    pub(crate) introduction: String,
    pub(crate) conclusion: String,
    pub(crate) steps: Vec<Step>,
    #[serde(default)]
    pub(crate) continues: bool,
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;

    /// An accessibility element at the given bounds, with its label as its id.
    pub(crate) fn element(label: &str, role: &str, x: f64, y: f64, width: f64, height: f64) -> Element {
        Element {
            id: label.to_string(),
            label: label.to_string(),
            role: role.to_string(),
            bounds: Rect { x, y, width, height },
            source: "ax".to_string(),
            context: String::new(),
            detail: String::new(),
            web: false,
        }
    }

    #[test]
    fn optional_fields_default() {
        let e: Element = serde_json::from_str(
            r#"{"id":"1","label":"OK","role":"AXButton","bounds":{"x":0,"y":0,"width":0.1,"height":0.1}}"#,
        )
        .unwrap();
        assert_eq!(
            (e.source.as_str(), e.context.as_str(), e.detail.as_str(), e.web),
            ("", "", "", false)
        );
        let s: Step = serde_json::from_str(r#"{"title":"t","explanation":"e","target":"3"}"#).unwrap();
        assert!(s.ready, "a step is ready unless it says otherwise");
        assert!(!s.action);
    }
}
