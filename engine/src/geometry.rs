//! Rectangles and the few measurements the engine makes with them.
//!
//! Every position is a fraction of the client's reference rectangle (usually the focused window) with a top-left
//! origin, so `0.0..=1.0` spans the whole window on both axes.

use serde::{Deserialize, Serialize};

use crate::model::Element;

/// A rectangle as fractions of the observed frame, top-left origin.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub(crate) struct Rect {
    pub(crate) x: f64,
    pub(crate) y: f64,
    pub(crate) width: f64,
    pub(crate) height: f64,
}

impl Rect {
    /// Finite, not empty, and inside the frame, allowing a little rounding past the far edges.
    pub(crate) fn valid(&self) -> bool {
        [self.x, self.y, self.width, self.height].iter().all(|v| v.is_finite())
            && self.x >= 0.0
            && self.y >= 0.0
            && self.width > 0.0
            && self.height > 0.0
            && self.x + self.width <= 1.005
            && self.y + self.height <= 1.005
    }

    /// The middle point, kept just inside the frame so it always falls in one of the nine regions.
    pub(crate) fn center(&self) -> (f64, f64) {
        (
            (self.x + self.width / 2.0).clamp(0.0, 0.999),
            (self.y + self.height / 2.0).clamp(0.0, 0.999),
        )
    }

    /// One of nine regions, row-major from the top left.
    pub(crate) fn cell(&self) -> usize {
        let (x, y) = self.center();
        (y * 3.0) as usize * 3 + (x * 3.0) as usize
    }

    /// The region's name, as the model reads it.
    pub(crate) fn place(&self) -> &'static str {
        [
            "top left",
            "top",
            "top right",
            "left",
            "center",
            "right",
            "bottom left",
            "bottom",
            "bottom right",
        ][self.cell()]
    }
}

/// `rect` expressed as fractions of `frame`, so positions read relative to a chosen area.
pub(crate) fn within(rect: &Rect, frame: &Rect) -> Rect {
    let x = ((rect.x - frame.x) / frame.width).clamp(0.0, 1.0);
    let y = ((rect.y - frame.y) / frame.height).clamp(0.0, 1.0);
    let w = (rect.width / frame.width).min(1.0 - x).max(0.001);
    let h = (rect.height / frame.height).min(1.0 - y).max(0.001);
    Rect {
        x,
        y,
        width: w,
        height: h,
    }
}

/// The union of the elements' bounds.
pub(crate) fn union(found: &[&Element]) -> Rect {
    let x0 = found.iter().map(|m| m.bounds.x).fold(f64::MAX, f64::min);
    let y0 = found.iter().map(|m| m.bounds.y).fold(f64::MAX, f64::min);
    let x1 = found.iter().map(|m| m.bounds.x + m.bounds.width).fold(0.0, f64::max);
    let y1 = found.iter().map(|m| m.bounds.y + m.bounds.height).fold(0.0, f64::max);
    Rect {
        x: x0,
        y: y0,
        width: x1 - x0,
        height: y1 - y0,
    }
}

/// Whether two rectangles share some area. Touching edges don't count.
pub(crate) fn overlaps(a: &Rect, b: &Rect) -> bool {
    a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.y + b.height && b.y < a.y + a.height
}

/// Whether at least 70% of `rect` lies inside `region`.
pub(crate) fn mostly_inside(rect: &Rect, region: &Rect) -> bool {
    let w = ((rect.x + rect.width).min(region.x + region.width) - rect.x.max(region.x)).max(0.0);
    let h = ((rect.y + rect.height).min(region.y + region.height) - rect.y.max(region.y)).max(0.0);
    w * h >= 0.7 * rect.width * rect.height
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::tests::element;

    fn rect(x: f64, y: f64, width: f64, height: f64) -> Rect {
        Rect { x, y, width, height }
    }

    fn close(a: &Rect, b: &Rect) -> bool {
        [(a.x, b.x), (a.y, b.y), (a.width, b.width), (a.height, b.height)]
            .iter()
            .all(|(p, q)| (p - q).abs() < 1e-9)
    }

    #[test]
    fn valid_rejects_empty_outside_and_non_finite() {
        assert!(rect(0.0, 0.0, 1.0, 1.0).valid());
        assert!(
            rect(0.5, 0.5, 0.504, 0.504).valid(),
            "a little rounding past the edge is fine"
        );
        assert!(!rect(0.5, 0.5, 0.51, 0.1).valid());
        assert!(!rect(-0.01, 0.0, 0.1, 0.1).valid());
        assert!(!rect(0.1, 0.1, 0.0, 0.1).valid());
        assert!(!rect(0.1, 0.1, f64::NAN, 0.1).valid());
        assert!(!rect(f64::INFINITY, 0.1, 0.1, 0.1).valid());
    }

    #[test]
    fn cells_are_row_major_from_the_top_left() {
        assert_eq!(rect(0.0, 0.0, 0.1, 0.1).place(), "top left");
        assert_eq!(rect(0.4, 0.4, 0.2, 0.2).place(), "center");
        assert_eq!(rect(0.9, 0.9, 0.1, 0.1).cell(), 8);
        // A rectangle reaching the far edge still lands in the last region.
        assert_eq!(rect(0.0, 0.0, 1.0, 2.0).center(), (0.5, 0.999));
        assert_eq!(rect(0.0, 0.0, 1.0, 2.0).place(), "bottom");
    }

    #[test]
    fn within_measures_relative_to_the_frame() {
        let frame = rect(0.2, 0.4, 0.5, 0.4);
        assert!(close(
            &within(&rect(0.2, 0.4, 0.25, 0.1), &frame),
            &rect(0.0, 0.0, 0.5, 0.25)
        ));
        assert!(close(
            &within(&rect(0.45, 0.6, 0.1, 0.2), &frame),
            &rect(0.5, 0.5, 0.2, 0.5)
        ));
    }

    #[test]
    fn within_clamps_to_the_frame() {
        let frame = rect(0.2, 0.2, 0.5, 0.5);
        // Starts before the frame: pinned to its edge.
        let r = within(&rect(0.0, 0.0, 0.3, 0.3), &frame);
        assert!(close(&r, &rect(0.0, 0.0, 0.6, 0.6)));
        // Runs past the far edge: cut to what's left.
        let r = within(&rect(0.6, 0.6, 0.4, 0.4), &frame);
        assert!(close(&r, &rect(0.8, 0.8, 0.2, 0.2)));
        // Entirely past the far edge: kept as a sliver so it's still a rectangle.
        let r = within(&rect(0.9, 0.9, 0.1, 0.1), &frame);
        assert!(close(&r, &rect(1.0, 1.0, 0.001, 0.001)));
    }

    #[test]
    fn union_spans_every_element() {
        let a = element("a", "AXButton", 0.1, 0.2, 0.1, 0.1);
        let b = element("b", "AXButton", 0.5, 0.05, 0.2, 0.1);
        let c = element("c", "AXButton", 0.3, 0.6, 0.1, 0.3);
        assert!(close(&union(&[&a, &b, &c]), &rect(0.1, 0.05, 0.6, 0.85)));
        assert!(close(&union(&[&b]), &b.bounds));
    }

    #[test]
    fn overlaps_needs_shared_area() {
        let a = rect(0.25, 0.25, 0.25, 0.25);
        assert!(overlaps(&a, &rect(0.375, 0.375, 0.25, 0.25)));
        assert!(overlaps(&a, &rect(0.3, 0.3, 0.01, 0.01)), "one inside the other");
        assert!(!overlaps(&a, &rect(0.5, 0.25, 0.25, 0.25)), "touching edges");
        assert!(!overlaps(&a, &rect(0.25, 0.5, 0.25, 0.25)), "touching edges");
        assert!(!overlaps(&a, &rect(0.75, 0.75, 0.125, 0.125)));
    }

    #[test]
    fn mostly_inside_needs_seventy_percent() {
        let region = rect(0.0, 0.0, 0.5, 0.5);
        assert!(mostly_inside(&rect(0.1, 0.1, 0.1, 0.1), &region));
        assert!(mostly_inside(&rect(0.42, 0.1, 0.1, 0.1), &region));
        assert!(!mostly_inside(&rect(0.45, 0.1, 0.1, 0.1), &region));
        assert!(!mostly_inside(&rect(0.6, 0.6, 0.1, 0.1), &region));
    }
}
