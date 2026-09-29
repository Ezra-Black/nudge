//! Building a tour: which stops it makes and in what order, with runs of similar controls grouped into one stop.
//! In a chosen area, the tour then reads its pictures and its text, gathered into blocks.

use std::collections::{HashMap, HashSet};

use crate::{
    clipped,
    geometry::{mostly_inside, overlaps, union, within, Rect},
    model::Element,
    select::{interactive, is_text, kind, round_robin, tier},
    TEXT_BLOCKS,
};

/// A tour stop: one control, or a group of similar neighbouring controls explained and highlighted together.
pub(crate) struct Item {
    /// The control itself, or for a group, one element standing for all of them.
    pub(crate) element: Element,
    /// A group's controls. Empty for a single control.
    pub(crate) members: Vec<Element>,
}

impl Item {
    /// A stop for one element.
    fn single(element: Element) -> Self {
        Item {
            element,
            members: Vec::new(),
        }
    }
}

/// "button" to "buttons", "text box" to "text boxes".
pub(crate) fn plural(k: &str) -> String {
    if k.ends_with('x') || k.ends_with('s') {
        format!("{k}es")
    } else {
        format!("{k}s")
    }
}

/// Number keys, symbol keys and worded controls don't group with each other.
fn label_class(label: &str) -> u8 {
    let t = label.trim();
    if !t.is_empty() && t.chars().all(|c| c.is_ascii_digit()) {
        0
    } else if t.chars().count() <= 2 && !t.chars().any(|c| c.is_alphanumeric()) {
        1
    } else {
        2
    }
}

/// Same kind of control in the same part of the window, of similar size, lined up or tiled side by side.
fn similar(a: &Element, b: &Element) -> bool {
    if a.role != b.role || a.context != b.context || label_class(&a.label) != label_class(&b.label) {
        return false;
    }
    let (ra, rb) = (&a.bounds, &b.bounds);
    let close = |x: f64, y: f64| (x - y).abs() <= 0.25 * x.max(y);
    if !close(ra.height, rb.height) {
        return false;
    }
    let gap_x = (rb.x - (ra.x + ra.width)).max(ra.x - (rb.x + rb.width)).max(0.0);
    let gap_y = (rb.y - (ra.y + ra.height)).max(ra.y - (rb.y + rb.height)).max(0.0);
    if gap_x > ra.width.max(rb.width) * 1.2 || gap_y > ra.height.max(rb.height) * 1.2 {
        return false;
    }
    let (ax, ay) = ra.center();
    let (bx, by) = rb.center();
    let row = (ay - by).abs() < ra.height.min(rb.height) * 0.5;
    let column = (ax - bx).abs() < ra.width.min(rb.width) * 0.5 || (ra.x - rb.x).abs() < 0.01;
    close(ra.width, rb.width) || row || column
}

/// One stop for several controls: highlighted as the box around them all, labeled with their labels in reading order.
fn group(mut members: Vec<Element>) -> Item {
    members.sort_by(|a, b| {
        let (ax, ay) = a.bounds.center();
        let (bx, by) = b.bounds.center();
        ((ay * 48.0) as i32).cmp(&((by * 48.0) as i32)).then(ax.total_cmp(&bx))
    });
    let bounds = union(&members.iter().collect::<Vec<_>>());
    let labels: Vec<&str> = members.iter().map(|m| m.label.as_str()).collect();
    let first = &members[0];
    let element = Element {
        id: format!("group:{}", first.id),
        label: clipped(&labels.join(", "), 120),
        role: first.role.clone(),
        bounds,
        source: first.source.clone(),
        context: first.context.clone(),
        detail: String::new(),
        web: first.web,
    };
    Item { element, members }
}

/// Groups runs of similar controls (a keypad's number keys, a row of tabs, a menu of links) into one stop.
fn clusters(controls: &[Element]) -> Vec<Item> {
    let n = controls.len();
    let mut parent: Vec<usize> = (0..n).collect();
    /// Union-find: the representative of `i`'s set, shortening the path on the way.
    fn root(parent: &mut [usize], mut i: usize) -> usize {
        while parent[i] != i {
            parent[i] = parent[parent[i]];
            i = parent[i];
        }
        i
    }
    for a in 0..n {
        for b in a + 1..n {
            if similar(&controls[a], &controls[b]) {
                let (x, y) = (root(&mut parent, a), root(&mut parent, b));
                if x != y {
                    parent[y] = x;
                }
            }
        }
    }
    let mut sets: Vec<(usize, Vec<usize>)> = Vec::new();
    for i in 0..n {
        let r = root(&mut parent, i);
        if let Some(at) = sets.iter().position(|(k, _)| *k == r) {
            sets[at].1.push(i)
        } else {
            sets.push((r, vec![i]))
        }
    }
    let mut items = Vec::new();
    for (_, members) in sets {
        // Worded controls need more company before they read as one thing.
        let needed = if label_class(&controls[members[0]].label) == 2 {
            4
        } else {
            3
        };
        if members.len() >= needed {
            items.push(group(members.iter().map(|&i| controls[i].clone()).collect()));
        } else {
            items.extend(members.into_iter().map(|i| Item::single(controls[i].clone())));
        }
    }
    items
}

/// A labeled part of the window, such as a toolbar or a sidebar, but not a heading.
fn is_area(e: &Element) -> bool {
    tier(e) == 0 && e.role != "AXHeading"
}

/// The stops a tour makes, one part of the window at a time, each part read top to bottom.
pub(crate) fn tour_queue(elements: &[Element], limit: usize, grouping: bool) -> Vec<Item> {
    let mut seen = HashSet::new();
    // Repeated controls (a Reply button on every row) are explained once. Links differ by destination.
    let controls: Vec<Element> = elements
        .iter()
        .filter(|e| {
            interactive(e)
                && seen.insert(format!(
                    "{}|{}|{}",
                    kind(&e.role),
                    e.label.to_lowercase(),
                    e.detail.to_lowercase()
                ))
        })
        .cloned()
        .collect();
    let items = if grouping {
        clusters(&controls)
    } else {
        controls.into_iter().map(Item::single).collect()
    };
    let reps: Vec<Element> = items.iter().map(|it| it.element.clone()).collect();
    let all: Vec<usize> = (0..reps.len()).collect();
    let picked = round_robin(&reps, &all, limit);
    let part = |e: &Element| {
        if e.context.is_empty() {
            format!("#{}", e.bounds.cell())
        } else {
            e.context.clone()
        }
    };
    let mut groups: Vec<(String, Vec<usize>)> = Vec::new();
    for i in picked {
        let key = part(&reps[i]);
        if let Some(at) = groups.iter().position(|(k, _)| *k == key) {
            groups[at].1.push(i)
        } else {
            groups.push((key, vec![i]))
        }
    }
    let at = |i: usize, bands: f64| {
        let (x, y) = reps[i].bounds.center();
        ((y * bands) as i32, x)
    };
    for (_, members) in &mut groups {
        members.sort_by(|&a, &b| {
            let (ya, xa) = at(a, 24.0);
            let (yb, xb) = at(b, 24.0);
            ya.cmp(&yb).then(xa.total_cmp(&xb))
        });
    }
    groups.sort_by(|(_, a), (_, b)| {
        let (ya, xa) = at(a[0], 4.0);
        let (yb, xb) = at(b[0], 4.0);
        ya.cmp(&yb).then(xa.total_cmp(&xb))
    });
    let mut slots: Vec<Option<Item>> = items.into_iter().map(Some).collect();
    let mut queue = Vec::new();
    for (key, members) in groups {
        // A labeled part of the window (a sidebar, a toolbar) introduces its own controls.
        if let Some(area) = elements.iter().find(|e| is_area(e) && e.label == key) {
            queue.push(Item::single(area.clone()));
        }
        queue.extend(members.into_iter().filter_map(|i| slots[i].take()));
    }
    queue
}

/// The stops after a chosen area's controls: its pictures, then its text in blocks. `region` is the area as
/// fractions of the observed frame. Also returns where each stop was found in the window, keyed by its target:
/// these come from a picture of the area, so later reads without one can't find them again.
pub(crate) fn area_stops(elements: &[Element], region: &Rect) -> (Vec<Item>, HashMap<String, Rect>) {
    let inside = |e: &Element| mostly_inside(&e.bounds, region);
    let mut stops = Vec::new();
    let mut fixed = HashMap::new();
    // Words on a button or link were covered with the control.
    let controls: Vec<&Element> = elements.iter().filter(|e| interactive(e) && inside(e)).collect();
    let on_control = |e: &Element| {
        let (x, y) = (e.bounds.x + e.bounds.width / 2.0, e.bounds.y + e.bounds.height / 2.0);
        controls.iter().any(|c| {
            c.bounds.x <= x && x <= c.bounds.x + c.bounds.width && c.bounds.y <= y && y <= c.bounds.y + c.bounds.height
        })
    };
    // Pictures next, each named from what it looks like, then the text.
    let mut pictures: Vec<&Element> = elements.iter().filter(|e| e.role == "picture" && inside(e)).collect();
    pictures.sort_by(|a, b| {
        ((a.bounds.y * 24.0) as i32)
            .cmp(&((b.bounds.y * 24.0) as i32))
            .then(a.bounds.x.total_cmp(&b.bounds.x))
    });
    for e in pictures {
        let mut shown = e.clone();
        shown.bounds = within(&e.bounds, region);
        stops.push(Item::single(shown));
        fixed.insert(e.id.clone(), e.bounds.clone());
    }
    let texts: Vec<Element> = elements
        .iter()
        .filter(|e| (is_text(e) || e.role == "AXHeading") && inside(e) && !on_control(e))
        .cloned()
        .collect();
    for (n, block) in text_blocks(texts, TEXT_BLOCKS).into_iter().enumerate() {
        let span = union(&block.iter().collect::<Vec<_>>());
        let words: Vec<&str> = block.iter().map(|e| e.label.trim()).collect();
        let id = format!("text:{n}:{}", block[0].id);
        stops.push(Item::single(Element {
            id: id.clone(),
            label: clipped(&words.join(" "), 400),
            role: "AXTextBlock".into(),
            bounds: within(&span, region),
            source: "text".into(),
            context: String::new(),
            detail: String::new(),
            web: false,
        }));
        fixed.insert(id, span);
    }
    (stops, fixed)
}

/// Text in a chosen area gathered into the pieces a person reads as one (a heading, a paragraph, a caption),
/// in reading order. At most `most` blocks; when there are more, the closest neighbours merge.
pub(crate) fn text_blocks(texts: Vec<Element>, most: usize) -> Vec<Vec<Element>> {
    let mut lines: Vec<Element> = Vec::new();
    for e in texts {
        // The same words reported twice (a heading and the text inside it) are read once. Stray marks are skipped.
        let repeated = lines
            .iter()
            .any(|l| l.label.trim().eq_ignore_ascii_case(e.label.trim()) && overlaps(&l.bounds, &e.bounds));
        if !repeated && e.label.chars().filter(|c| c.is_alphanumeric()).count() >= 2 {
            lines.push(e);
        }
    }
    lines.sort_by(|a, b| {
        a.bounds
            .y
            .total_cmp(&b.bounds.y)
            .then(a.bounds.x.total_cmp(&b.bounds.x))
    });
    let mut blocks: Vec<Vec<Element>> = Vec::new();
    for line in lines {
        let r = line.bounds.clone();
        // A line continues a block when it's the next line down at the same size, or the rest of the same line.
        let joins = |block: &Vec<Element>| {
            let last = &block[block.len() - 1].bounds;
            let h = last.height.min(r.height);
            let same_size = (last.height - r.height).abs() <= 0.35 * last.height.max(r.height);
            let gap_y = r.y - (last.y + last.height);
            let gap_x = r.x - (last.x + last.width);
            let same_row = ((last.y + last.height / 2.0) - (r.y + r.height / 2.0)).abs() < h * 0.5;
            let lined_up = (last.x + last.width).min(r.x + r.width) > last.x.max(r.x) || (r.x - last.x).abs() < h * 2.0;
            (same_row && gap_x > -h && gap_x < h * 2.0)
                || (same_size && gap_y > -h * 0.5 && gap_y < h * 0.9 && lined_up)
        };
        match blocks.iter_mut().rev().take(3).find(|b| joins(b)) {
            Some(block) => block.push(line),
            None => blocks.push(vec![line]),
        }
    }
    let span = |b: &Vec<Element>| union(&b.iter().collect::<Vec<_>>());
    while blocks.len() > most.max(1) {
        let gap = |i: usize| {
            let (a, b) = (span(&blocks[i]), span(&blocks[i + 1]));
            (b.y - (a.y + a.height)).max(a.y - (b.y + b.height)).max(0.0)
        };
        let Some(i) = (0..blocks.len() - 1).min_by(|&i, &j| gap(i).total_cmp(&gap(j))) else {
            break;
        };
        let next = blocks.remove(i + 1);
        blocks[i].extend(next);
    }
    blocks
}

/// A short heading for a block of text until the model names it: its first few words.
pub(crate) fn opening(text: &str) -> String {
    let words: Vec<&str> = text.split_whitespace().collect();
    format!(
        "“{}{}”",
        words[..words.len().min(6)].join(" "),
        if words.len() > 6 { "…" } else { "" }
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::tests::element;

    fn key(label: &str, col: usize, row: usize) -> Element {
        let mut e = element(
            label,
            "AXButton",
            0.1 + col as f64 * 0.07,
            0.3 + row as f64 * 0.07,
            0.06,
            0.06,
        );
        e.context = "Keypad".to_string();
        e
    }

    fn ocr(label: &str, x: f64, y: f64, width: f64, height: f64) -> Element {
        let mut e = element(label, "visible text", x, y, width, height);
        e.source = "ocr".to_string();
        e
    }

    fn labels(block: &[Element]) -> Vec<&str> {
        block.iter().map(|e| e.label.as_str()).collect()
    }

    #[test]
    fn a_number_keypad_is_one_stop() {
        let keys: Vec<Element> = (1..=9).map(|n| key(&n.to_string(), (n - 1) % 3, (n - 1) / 3)).collect();
        let items = clusters(&keys);
        assert_eq!(items.len(), 1);
        let group = &items[0];
        assert_eq!(group.members.len(), 9);
        assert_eq!(group.element.id, "group:1");
        assert_eq!(group.element.label, "1, 2, 3, 4, 5, 6, 7, 8, 9");
        assert_eq!(group.element.context, "Keypad");
        let b = &group.element.bounds;
        assert!((b.x - 0.1).abs() < 1e-9 && (b.y - 0.3).abs() < 1e-9);
        assert!((b.width - 0.2).abs() < 1e-9 && (b.height - 0.2).abs() < 1e-9);
    }

    #[test]
    fn numbers_and_symbols_group_separately() {
        let mut keys: Vec<Element> = (1..=3).map(|n| key(&n.to_string(), n - 1, 0)).collect();
        keys.extend(["+", "−", "×"].iter().enumerate().map(|(row, s)| key(s, 3, row)));
        let items = clusters(&keys);
        assert_eq!(items.len(), 2);
        assert_eq!(items[0].element.label, "1, 2, 3");
        assert_eq!(items[1].element.label, "+, −, ×");
    }

    #[test]
    fn two_similar_worded_buttons_stay_apart() {
        let buttons = vec![key("Back", 0, 0), key("Forward", 1, 0)];
        let items = clusters(&buttons);
        assert_eq!(items.len(), 2);
        assert!(items.iter().all(|it| it.members.is_empty()));
        assert_eq!(items[0].element.id, "Back");
    }

    #[test]
    fn four_worded_tabs_group() {
        let tabs: Vec<Element> = ["General", "Tabs", "Privacy", "Advanced"]
            .iter()
            .enumerate()
            .map(|(i, t)| key(t, i, 0))
            .collect();
        assert_eq!(clusters(&tabs).len(), 1);
        // Three are not enough.
        assert_eq!(clusters(&tabs[..3]).len(), 3);
    }

    #[test]
    fn controls_far_apart_or_of_other_kinds_stay_apart() {
        let mut far = key("2", 0, 0);
        far.bounds.x = 0.8;
        let mut other_part = key("3", 2, 0);
        other_part.context = "Footer".to_string();
        let mut link = key("4", 1, 1);
        link.role = "AXLink".to_string();
        let keys = vec![key("1", 0, 0), far, other_part, link];
        assert_eq!(clusters(&keys).len(), 4);
    }

    #[test]
    fn tour_queue_introduces_areas_and_explains_repeats_once() {
        let toolbar = element("Toolbar", "AXToolbar", 0.0, 0.0, 1.0, 0.1);
        let mut back = element("Back", "AXButton", 0.01, 0.02, 0.05, 0.05);
        back.context = "Toolbar".to_string();
        let reply = element("Reply", "AXButton", 0.1, 0.5, 0.1, 0.05);
        let mut reply_again = element("Reply", "AXButton", 0.1, 0.7, 0.1, 0.05);
        reply_again.id = "Reply 2".to_string();
        let elements = vec![reply, toolbar, reply_again, back];
        let ids: Vec<String> = tour_queue(&elements, 36, true)
            .into_iter()
            .map(|it| it.element.id)
            .collect();
        assert_eq!(ids, ["Toolbar", "Back", "Reply"]);
        // The limit counts controls; an area still introduces the ones picked.
        let ids: Vec<String> = tour_queue(&elements, 1, true)
            .into_iter()
            .map(|it| it.element.id)
            .collect();
        assert_eq!(ids, ["Toolbar", "Back"]);
    }

    #[test]
    fn a_heading_and_a_paragraph_are_separate_blocks() {
        let texts = vec![
            ocr("Meet Biscuit", 0.1, 0.1, 0.3, 0.06),
            ocr("Biscuit is a friendly two year old", 0.1, 0.19, 0.3, 0.025),
            ocr("terrier who loves long walks", 0.1, 0.22, 0.28, 0.025),
            ocr("and naps in the sun.", 0.1, 0.25, 0.2, 0.025),
        ];
        let blocks = text_blocks(texts, 8);
        assert_eq!(blocks.len(), 2);
        assert_eq!(labels(&blocks[0]), ["Meet Biscuit"]);
        assert_eq!(blocks[1].len(), 3);
    }

    #[test]
    fn pieces_of_one_line_join_in_reading_order() {
        let texts = vec![
            ocr("terrier mix.", 0.46, 0.34, 0.1, 0.025),
            ocr("Biscuit is a friendly two year old", 0.2, 0.34, 0.25, 0.025),
            ocr("Far away on the right", 0.8, 0.34, 0.15, 0.025),
        ];
        let blocks = text_blocks(texts, 8);
        assert_eq!(blocks.len(), 2);
        assert_eq!(
            labels(&blocks[0]),
            ["Biscuit is a friendly two year old", "terrier mix."]
        );
        assert_eq!(labels(&blocks[1]), ["Far away on the right"]);
    }

    #[test]
    fn repeated_words_and_stray_marks_are_skipped() {
        let texts = vec![
            ocr("Meet Biscuit", 0.1, 0.1, 0.3, 0.06),
            ocr("meet biscuit", 0.11, 0.11, 0.28, 0.05),
            ocr("•", 0.05, 0.3, 0.01, 0.02),
            ocr("A1", 0.5, 0.5, 0.05, 0.02),
        ];
        let blocks = text_blocks(texts, 8);
        assert_eq!(blocks.len(), 2);
        assert_eq!(labels(&blocks[0]), ["Meet Biscuit"]);
        assert_eq!(labels(&blocks[1]), ["A1"]);
    }

    #[test]
    fn the_closest_blocks_merge_down_to_the_limit() {
        // Five headings far apart; the second and third are closest.
        let texts: Vec<Element> = [0.0, 0.2, 0.3, 0.5, 0.8]
            .iter()
            .enumerate()
            .map(|(i, y)| ocr(&format!("Heading {i}"), 0.1, *y, 0.3, 0.04))
            .collect();
        assert_eq!(text_blocks(texts.clone(), 8).len(), 5);
        let blocks = text_blocks(texts.clone(), 4);
        assert_eq!(blocks.len(), 4);
        assert_eq!(labels(&blocks[1]), ["Heading 1", "Heading 2"]);
        assert_eq!(text_blocks(texts.clone(), 1).len(), 1);
        assert_eq!(text_blocks(texts, 0).len(), 1, "always at least one block");
    }

    #[test]
    fn area_stops_read_pictures_then_text_but_not_words_on_controls() {
        let region = Rect {
            x: 0.0,
            y: 0.0,
            width: 0.5,
            height: 0.5,
        };
        let mut picture = element("Photo", "picture", 0.25, 0.25, 0.125, 0.125);
        picture.source = "vision".to_string();
        let elements = vec![
            element("Adopt", "AXButton", 0.25, 0.4, 0.1, 0.05),
            ocr("Adopt", 0.26, 0.41, 0.08, 0.03),
            ocr("Meet Biscuit", 0.05, 0.05, 0.2, 0.05),
            ocr("Outside", 0.7, 0.7, 0.2, 0.05),
            picture,
        ];
        let (stops, fixed) = area_stops(&elements, &region);
        let ids: Vec<&str> = stops.iter().map(|it| it.element.id.as_str()).collect();
        assert_eq!(ids, ["Photo", "text:0:Meet Biscuit"]);
        assert_eq!(stops[1].element.role, "AXTextBlock");
        let b = &stops[0].element.bounds;
        assert_eq!(
            (b.x, b.y, b.width, b.height),
            (0.5, 0.5, 0.25, 0.25),
            "measured within the area"
        );
        let found = &fixed["Photo"];
        assert_eq!(
            (found.x, found.y),
            (0.25, 0.25),
            "kept where it was found in the window"
        );
        assert!(fixed.contains_key("text:0:Meet Biscuit"));
    }

    #[test]
    fn opening_is_the_first_six_words() {
        assert_eq!(opening("Meet Biscuit"), "“Meet Biscuit”");
        assert_eq!(
            opening("one two three four five six seven"),
            "“one two three four five six…”"
        );
        assert_eq!(opening(""), "“”");
    }

    #[test]
    fn plurals() {
        assert_eq!(plural("button"), "buttons");
        assert_eq!(plural("checkbox"), "checkboxes");
        assert_eq!(plural("text field"), "text fields");
    }
}
