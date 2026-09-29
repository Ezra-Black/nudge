//! What kind of thing each element is, and which elements the model is shown.

use std::collections::HashSet;

use crate::{model::Element, PROMPT_LIMIT};

/// Words on the screen rather than a control: read from a screenshot, or plain text.
pub(crate) fn is_text(e: &Element) -> bool {
    e.source == "ocr" || e.role == "AXStaticText"
}

/// Lower tiers are offered to the model first: areas and headings, then controls, icons, then plain text.
pub(crate) fn tier(e: &Element) -> u8 {
    match e.role.as_str() {
        "AXHeading" | "AXToolbar" | "AXTabGroup" | "AXOutline" | "AXTable" | "AXList" | "AXGroup" | "AXScrollArea" => 0,
        "AXImage" => 2,
        _ if is_text(e) => 3,
        _ => 1,
    }
}

/// What a role is called in prompts and fallback text: `AXPopUpButton` is a "pop-up menu".
pub(crate) fn kind(role: &str) -> &str {
    match role {
        "AXButton" => "button",
        "AXCheckBox" => "checkbox",
        "AXRadioButton" => "option",
        "AXPopUpButton" => "pop-up menu",
        "AXMenuButton" => "menu button",
        "AXTextField" => "text field",
        "AXSearchField" => "search field",
        "AXTextArea" => "text area",
        "AXComboBox" => "combo box",
        "AXSlider" => "slider",
        "AXLink" => "link",
        "AXTextBlock" => "text",
        "AXTabGroup" => "tabs",
        "AXHeading" => "heading",
        "AXStaticText" => "text",
        "AXImage" => "icon",
        "AXToolbar" => "toolbar",
        "AXOutline" | "AXList" => "list",
        "AXTable" => "table",
        "AXGroup" | "AXScrollArea" => "area",
        "AXMenuBarItem" => "menu",
        "AXDisclosureTriangle" => "disclosure arrow",
        "AXIncrementor" => "stepper",
        "AXColorWell" => "color picker",
        other => other.trim_start_matches("AX"),
    }
}

/// A control someone can use, found through accessibility. Only these become tour stops of their own.
pub(crate) fn interactive(e: &Element) -> bool {
    e.source == "ax"
        && matches!(
            e.role.as_str(),
            "AXButton"
                | "AXLink"
                | "AXPopUpButton"
                | "AXMenuButton"
                | "AXCheckBox"
                | "AXRadioButton"
                | "AXTextField"
                | "AXSearchField"
                | "AXTextArea"
                | "AXComboBox"
                | "AXSlider"
                | "AXDisclosureTriangle"
                | "AXIncrementor"
                | "AXColorWell"
        )
}

/// Picks a spatially balanced subset so one busy toolbar or menu can't crowd out the rest of the window.
pub(crate) fn select(elements: &[Element]) -> Vec<Element> {
    let mut seen = HashSet::new();
    let pool: Vec<usize> = (0..elements.len())
        .filter(|&i| !is_text(&elements[i]) || seen.insert(elements[i].label.to_lowercase()))
        .collect();
    let (controls, texts): (Vec<usize>, Vec<usize>) = pool.into_iter().partition(|&i| tier(&elements[i]) < 3);
    // Visible text says what the window is showing; keep room for it beside the controls.
    let text_take = texts.len().min(PROMPT_LIMIT * 2 / 5);
    let control_take = controls.len().min(PROMPT_LIMIT - text_take);
    let text_take = texts.len().min(PROMPT_LIMIT - control_take);
    let mut chosen = round_robin(elements, &controls, control_take);
    chosen.extend(round_robin(elements, &texts, text_take));
    // Reading order, so numbering follows the layout the person sees.
    chosen.sort_by(|&a, &b| {
        let (ax, ay) = elements[a].bounds.center();
        let (bx, by) = elements[b].bounds.center();
        ((ay * 12.0) as i32).cmp(&((by * 12.0) as i32)).then(ax.total_cmp(&bx))
    });
    chosen.into_iter().map(|i| elements[i].clone()).collect()
}

/// Up to `take` of `indices`, one from each of the nine regions in turn, lowest tier first within a region.
pub(crate) fn round_robin(elements: &[Element], indices: &[usize], take: usize) -> Vec<usize> {
    let mut cells: Vec<Vec<usize>> = vec![Vec::new(); 9];
    for &i in indices {
        cells[elements[i].bounds.cell()].push(i);
    }
    for c in &mut cells {
        c.sort_by_key(|&i| (tier(&elements[i]), i));
    }
    let mut out = Vec::new();
    for round in 0.. {
        let mut any = false;
        for c in &cells {
            if out.len() < take {
                if let Some(&i) = c.get(round) {
                    out.push(i);
                    any = true;
                }
            }
        }
        if !any || out.len() >= take {
            break;
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::tests::element;

    fn text(label: &str, x: f64, y: f64) -> Element {
        let mut e = element(label, "visible text", x, y, 0.1, 0.02);
        e.source = "ocr".to_string();
        e
    }

    /// A toolbar crowded with buttons along the top, and one button in each other region.
    fn busy_window() -> Vec<Element> {
        let mut elements: Vec<Element> = (0..100)
            .map(|i| element(&format!("Tool {i}"), "AXButton", 0.0099 * i as f64, 0.01, 0.009, 0.04))
            .collect();
        for (n, (x, y)) in [(0.1, 0.5), (0.5, 0.5), (0.9, 0.5), (0.1, 0.9), (0.5, 0.9), (0.9, 0.9)]
            .iter()
            .enumerate()
        {
            elements.push(element(
                &format!("Lone {n}"),
                "AXButton",
                *x - 0.02,
                *y - 0.02,
                0.04,
                0.04,
            ));
        }
        elements
    }

    #[test]
    fn classifies_roles() {
        assert_eq!(kind("AXPopUpButton"), "pop-up menu");
        assert_eq!(kind("AXSomethingNew"), "SomethingNew");
        assert_eq!(kind("picture"), "picture");
        assert_eq!(tier(&element("Sidebar", "AXGroup", 0.0, 0.0, 0.1, 0.1)), 0);
        assert_eq!(tier(&element("OK", "AXButton", 0.0, 0.0, 0.1, 0.1)), 1);
        assert_eq!(tier(&element("Logo", "AXImage", 0.0, 0.0, 0.1, 0.1)), 2);
        assert_eq!(tier(&text("Hello", 0.0, 0.0)), 3);
        assert!(interactive(&element("OK", "AXButton", 0.0, 0.0, 0.1, 0.1)));
        assert!(!interactive(&element("Title", "AXHeading", 0.0, 0.0, 0.1, 0.1)));
        let mut ocr_button = element("OK", "AXButton", 0.0, 0.0, 0.1, 0.1);
        ocr_button.source = "ocr".to_string();
        assert!(!interactive(&ocr_button), "only accessibility controls can be used");
    }

    #[test]
    fn select_keeps_every_region_when_one_is_crowded() {
        let chosen = select(&busy_window());
        assert_eq!(chosen.len(), PROMPT_LIMIT);
        for n in 0..6 {
            assert!(
                chosen.iter().any(|e| e.label == format!("Lone {n}")),
                "Lone {n} was crowded out"
            );
        }
    }

    #[test]
    fn select_leaves_room_for_text_but_not_more() {
        let mut elements = busy_window();
        elements.extend((0..50).map(|i| text(&format!("Line {i}"), 0.3, 0.3 + 0.001 * i as f64)));
        let chosen = select(&elements);
        assert_eq!(chosen.len(), PROMPT_LIMIT);
        assert_eq!(chosen.iter().filter(|e| is_text(e)).count(), PROMPT_LIMIT * 2 / 5);

        // With few controls, text fills the rest.
        let mut elements = vec![element("OK", "AXButton", 0.1, 0.1, 0.1, 0.1)];
        elements.extend((0..80).map(|i| text(&format!("Line {i}"), 0.3, 0.001 * i as f64)));
        let chosen = select(&elements);
        assert_eq!(chosen.len(), PROMPT_LIMIT);
        assert_eq!(chosen.iter().filter(|e| is_text(e)).count(), PROMPT_LIMIT - 1);
    }

    #[test]
    fn select_reads_repeated_text_once_and_in_reading_order() {
        let elements = vec![
            element("Save", "AXButton", 0.8, 0.8, 0.1, 0.05),
            text("Welcome", 0.1, 0.1),
            text("welcome", 0.5, 0.5),
            element("Menu", "AXButton", 0.1, 0.8, 0.1, 0.05),
            element("Close", "AXButton", 0.8, 0.1, 0.1, 0.05),
        ];
        let labels: Vec<String> = select(&elements).into_iter().map(|e| e.label).collect();
        assert_eq!(labels, ["Welcome", "Close", "Menu", "Save"]);
    }

    #[test]
    fn round_robin_takes_lower_tiers_first_within_a_region() {
        let elements = vec![
            text("Hello", 0.1, 0.1),
            element("OK", "AXButton", 0.1, 0.1, 0.1, 0.1),
            element("Toolbar", "AXToolbar", 0.0, 0.0, 0.3, 0.1),
            element("Far", "AXButton", 0.8, 0.8, 0.1, 0.1),
        ];
        assert_eq!(round_robin(&elements, &[0, 1, 2, 3], 3), [2, 3, 1]);
        assert_eq!(round_robin(&elements, &[0, 1, 2, 3], 10), [2, 3, 1, 0]);
        assert!(round_robin(&elements, &[0, 1], 0).is_empty());
    }
}
