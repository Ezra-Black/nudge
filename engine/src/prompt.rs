//! The text the on-device model reads, and the plain descriptions used when it says nothing.
//!
//! The model's context window is small: items are one short line each, and long labels are clipped.
//! Items are numbered so the model can refer to them; `install` and `explain` map the numbers back to elements.

use crate::{
    clipped,
    model::{Element, Observation},
    select::kind,
    tour::{plural, Item},
};

/// One item as the model reads it: `number | kind | label | position | part of window | details`.
/// `members` is the size of a group, or 0 or 1 for a single element.
pub(crate) fn item_line(i: usize, e: &Element, members: usize) -> String {
    let k = if members > 1 {
        format!("group of {members} {}", plural(kind(&e.role)))
    } else {
        kind(&e.role).to_string()
    };
    let part = if e.context.is_empty() {
        String::new()
    } else {
        format!(" | {}", clipped(&e.context, 32))
    };
    let detail = if e.detail.is_empty() {
        String::new()
    } else {
        format!(" | {}", clipped(&e.detail, 70))
    };
    let most = if e.role == "AXTextBlock" {
        240
    } else if members > 1 {
        100
    } else {
        56
    };
    format!(
        "{i} | {k} | {} | {}{part}{detail}",
        clipped(&e.label, most),
        e.bounds.place()
    )
}

/// ` Page: <address>.` for a web page, or nothing.
pub(crate) fn page_note(o: &Observation) -> String {
    if o.page.is_empty() {
        String::new()
    } else {
        format!(" Page: {}.", clipped(&o.page, 80))
    }
}

/// Asks for a tour's overview. `scope` is `all`, `web` (the page in a browser), `app` (the browser around it)
/// or `area` (a part of the window the person chose). `lines` are the chosen items, from [`item_line`].
pub(crate) fn overview_prompt(o: &Observation, scope: &str, lines: &[String]) -> String {
    let app = clipped(&o.app, 40);
    let lines = lines.join("\n");
    let task = match scope {
        "web" => "Write an overview of this web page: what the website is, what this page shows right now, and what \
                  someone can do here. Its links and buttons are explained separately afterwards."
            .to_string(),
        "app" => format!(
            "Write an overview of {app}'s own controls around the web page, such as its tabs, address bar and \
             toolbar: what they are for as a whole. Each control is explained separately afterwards."
        ),
        "area" => {
            let scene = if o.scene.is_empty() {
                String::new()
            } else {
                format!(
                    " The picture in the selection looks like it contains: {}.",
                    clipped(&o.scene, 120)
                )
            };
            format!(
                "Describe only what is inside the selection: what it is, what it shows or says, and what someone \
                 can do with it. Do not describe the rest of the window, the app, or the website as a whole. \
                 The visible text items are read from a picture of the selection.{scene}"
            )
        }
        _ => format!(
            "Write an overview of this {}: what it is, what it is showing right now, and what someone can do here \
             as a whole. Each button is explained separately afterwards.",
            if o.page.is_empty() { "window" } else { "page" }
        ),
    };
    // A chosen area is described on its own: no window title or page, which would draw the model to the whole app.
    if scope == "area" {
        format!(
            "The person selected one part of a window in {app}.\n\
             Items inside the selection (number | kind | label | position in the selection | part of window | \
             details):\n\
             {lines}\n\
             {task}"
        )
    } else {
        format!(
            "App: {app}. Window: {}.{}\n\
             Visible items (number | kind | label | position | part of window | details):\n\
             {lines}\n\
             {task}",
            clipped(&o.window, 80),
            page_note(o)
        )
    }
}

/// Asks for the one next action toward `goal`. `progress` is what the person has already done.
pub(crate) fn goal_prompt(o: &Observation, goal: &str, progress: &str, lines: &[String]) -> String {
    format!(
        "App: {}. Window: {}.{}\n\
         User goal: {goal}\n\
         Already done: {progress}\n\
         Visible items (number | kind | label | position | part of window | details):\n\
         {}\n\
         Give only the next useful action supported by a visible item. Do not plan unseen screens. \
         continues=true if further guidance will be needed after the action. \
         If the goal is visibly complete, return no steps and explain the result. \
         Never claim completion without evidence.",
        clipped(&o.app, 40),
        clipped(&o.window, 80),
        page_note(o),
        lines.join("\n")
    )
}

/// Asks the model to explain one batch of tour stops, numbered from 1. `area` is a tour of a chosen area.
pub(crate) fn batch_prompt(o: &Observation, items: &[Item], area: bool) -> String {
    let lines: Vec<_> = items
        .iter()
        .enumerate()
        .map(|(i, it)| item_line(i + 1, &it.element, it.members.len()))
        .collect();
    let lines = lines.join("\n");
    let app = clipped(&o.app, 40);
    if area {
        return format!(
            "These items are inside one part of a window in {app} that the person selected.\n\
             Items (number | kind | label | position in the selection | part of window | details):\n\
             {lines}\n\
             Explain every item above: one entry per item, in order, using the same numbers. \
             Say what each one is for within this selection and why someone would use it. \
             For a text item, say in plain words what the text says and what it means for the person; \
             do not just read it back. \
             For a picture, say what it shows using its details, for example “This is a photo of a dog.” \
             Do not describe the rest of the window, the app or the website. \
             Never just repeat the label."
        );
    }
    format!(
        "App: {app}. Window: {}.{}\n\
         Items (number | kind | label | position | part of window | details):\n\
         {lines}\n\
         Explain every item above: one entry per item, in order, using the same numbers. \
         Explain the purpose, not just the name: what happens when someone uses it and why they would. \
         Use what you know about {app} and common Mac and website conventions. \
         For a link, say where it goes and why someone would go there. \
         For a field, say what to type there. \
         For a group, explain what its controls are for together and how to use them. \
         For an area, say what that part of the window is for. \
         Never just repeat the label.",
        clipped(&o.window, 80),
        page_note(o)
    )
}

/// A factual explanation built only from what was observed, used when the model gives none.
pub(crate) fn fallback(item: &Item) -> String {
    let e = &item.element;
    let label = clipped(&e.label, 60);
    let k = kind(&e.role);
    if e.role == "picture" {
        return match e.detail.strip_prefix("looks like: ") {
            Some(d) if !d.trim().is_empty() => {
                let mut parts = d.split(", ");
                let first = parts.next().unwrap_or(d);
                let rest: Vec<&str> = parts.collect();
                if rest.is_empty() {
                    format!("This picture looks like it shows {first}.")
                } else {
                    format!(
                        "This picture looks like it shows {first}. I can also make out: {}.",
                        rest.join(", ")
                    )
                }
            }
            _ => "This is a picture. I can’t quite make out what it shows.".to_string(),
        };
    }
    if e.role == "AXTextBlock" {
        return format!(
            "This text says: “{}{}”",
            clipped(&e.label, 300),
            if e.label.chars().count() > 300 { "…" } else { "" }
        );
    }
    if item.members.len() > 1 {
        return format!(
            "These {} {} are: {}.",
            item.members.len(),
            plural(k),
            clipped(&e.label, 100)
        );
    }
    match e.detail.as_str() {
        "" => format!("This is the “{label}” {k}."),
        "on" | "off" => format!("This is the “{label}” {k}. It’s currently {}.", e.detail),
        d if e.role == "AXLink" => format!("This link {d}."),
        d => match d.strip_prefix("tip: ") {
            Some(tip) => format!("The “{label}” {k}: {tip}"),
            None => format!("This is the “{label}” {k} ({d})."),
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::tests::element;

    fn single(label: &str, role: &str, detail: &str) -> Item {
        let mut element = element(label, role, 0.1, 0.1, 0.1, 0.1);
        element.detail = detail.to_string();
        Item {
            element,
            members: Vec::new(),
        }
    }

    #[test]
    fn fallback_describes_pictures_from_what_they_look_like() {
        let many = single("Photo", "picture", "looks like: a dog, grass, a ball");
        assert_eq!(
            fallback(&many),
            "This picture looks like it shows a dog. I can also make out: grass, a ball."
        );
        let one = single("Photo", "picture", "looks like: a cat");
        assert_eq!(fallback(&one), "This picture looks like it shows a cat.");
        for unclear in ["", "looks like:  ", "a dog"] {
            let picture = single("Photo", "picture", unclear);
            assert_eq!(
                fallback(&picture),
                "This is a picture. I can’t quite make out what it shows."
            );
        }
    }

    #[test]
    fn fallback_reads_a_text_block() {
        let short = single("Meet Biscuit", "AXTextBlock", "");
        assert_eq!(fallback(&short), "This text says: “Meet Biscuit”");
        let long = single(&"word ".repeat(70), "AXTextBlock", "");
        let text = fallback(&long);
        assert!(text.ends_with("word …”"), "{text}");
        assert_eq!(text.chars().count(), "This text says: “".chars().count() + 300 + 2);
    }

    #[test]
    fn fallback_says_where_a_link_goes() {
        let link = single("Pricing", "AXLink", "goes to /pricing on this site");
        assert_eq!(fallback(&link), "This link goes to /pricing on this site.");
        let bare = single("Contact", "AXLink", "");
        assert_eq!(fallback(&bare), "This is the “Contact” link.");
    }

    #[test]
    fn fallback_gives_a_checkbox_state() {
        let on = single("Remember me", "AXCheckBox", "on");
        assert_eq!(fallback(&on), "This is the “Remember me” checkbox. It’s currently on.");
        let off = single("Remember me", "AXCheckBox", "off");
        assert_eq!(
            fallback(&off),
            "This is the “Remember me” checkbox. It’s currently off."
        );
    }

    #[test]
    fn fallback_uses_tips_details_and_groups() {
        let tip = single("Share", "AXButton", "tip: Send this page to someone");
        assert_eq!(fallback(&tip), "The “Share” button: Send this page to someone");
        let detail = single("Currency", "AXPopUpButton", "shows USD");
        assert_eq!(fallback(&detail), "This is the “Currency” pop-up menu (shows USD).");
        let mut group = single("1, 2, 3", "AXButton", "");
        group.members = vec![group.element.clone(); 3];
        assert_eq!(fallback(&group), "These 3 buttons are: 1, 2, 3.");
    }

    #[test]
    fn item_lines_name_kind_place_part_and_details() {
        let mut e = element("Pricing", "AXLink", 0.8, 0.1, 0.1, 0.05);
        e.context = "Sidebar".to_string();
        e.detail = "goes to /pricing on this site".to_string();
        assert_eq!(
            item_line(3, &e, 0),
            "3 | link | Pricing | top right | Sidebar | goes to /pricing on this site"
        );
        let keys = element("1, 2, 3", "AXButton", 0.1, 0.4, 0.2, 0.2);
        assert_eq!(item_line(1, &keys, 3), "1 | group of 3 buttons | 1, 2, 3 | left");
        let long = element(&"x".repeat(80), "AXButton", 0.4, 0.4, 0.1, 0.1);
        assert_eq!(
            item_line(0, &long, 0),
            format!("0 | button | {} | center", "x".repeat(56))
        );
    }
}
