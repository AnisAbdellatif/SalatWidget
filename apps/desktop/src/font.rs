//! A tiny 5×7 pixel font for drawing countdowns into tray icons, so no font files or
//! text rendering libraries are needed. Covers digits and the units `h`, `m`, `s`, `:`.

/// A glyph: its width in pixels and seven rows, most significant bit = leftmost pixel.
pub struct Glyph {
    pub width: u32,
    pub rows: [u8; 7],
}

pub const HEIGHT: u32 = 7;

pub fn glyph(c: char) -> Option<Glyph> {
    let (width, rows) = match c {
        '0' => (
            5,
            [
                0b01110, 0b10001, 0b10011, 0b10101, 0b11001, 0b10001, 0b01110,
            ],
        ),
        '1' => (
            5,
            [
                0b00100, 0b01100, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110,
            ],
        ),
        '2' => (
            5,
            [
                0b01110, 0b10001, 0b00001, 0b00010, 0b00100, 0b01000, 0b11111,
            ],
        ),
        '3' => (
            5,
            [
                0b11111, 0b00010, 0b00100, 0b00010, 0b00001, 0b10001, 0b01110,
            ],
        ),
        '4' => (
            5,
            [
                0b00010, 0b00110, 0b01010, 0b10010, 0b11111, 0b00010, 0b00010,
            ],
        ),
        '5' => (
            5,
            [
                0b11111, 0b10000, 0b11110, 0b00001, 0b00001, 0b10001, 0b01110,
            ],
        ),
        '6' => (
            5,
            [
                0b00110, 0b01000, 0b10000, 0b11110, 0b10001, 0b10001, 0b01110,
            ],
        ),
        '7' => (
            5,
            [
                0b11111, 0b00001, 0b00010, 0b00100, 0b01000, 0b01000, 0b01000,
            ],
        ),
        '8' => (
            5,
            [
                0b01110, 0b10001, 0b10001, 0b01110, 0b10001, 0b10001, 0b01110,
            ],
        ),
        '9' => (
            5,
            [
                0b01110, 0b10001, 0b10001, 0b01111, 0b00001, 0b00010, 0b01100,
            ],
        ),
        'h' => (
            5,
            [
                0b10000, 0b10000, 0b10110, 0b11001, 0b10001, 0b10001, 0b10001,
            ],
        ),
        'm' => (
            5,
            [
                0b00000, 0b00000, 0b11010, 0b10101, 0b10101, 0b10001, 0b10001,
            ],
        ),
        's' => (
            5,
            [
                0b00000, 0b00000, 0b01111, 0b10000, 0b01110, 0b00001, 0b11110,
            ],
        ),
        ':' => (1, [0b0, 0b1, 0b0, 0b0, 0b0, 0b1, 0b0]),
        _ => return None,
    };
    Some(Glyph { width, rows })
}

/// Width of `text` in font pixels, with one pixel between glyphs.
pub fn text_width(text: &str) -> u32 {
    let widths: Vec<u32> = text.chars().filter_map(glyph).map(|g| g.width).collect();
    widths.iter().sum::<u32>() + widths.len().saturating_sub(1) as u32
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn covers_every_character_the_countdown_uses() {
        for c in "0123456789hms:".chars() {
            assert!(glyph(c).is_some(), "missing glyph {c:?}");
        }
        assert!(glyph('x').is_none());
    }

    #[test]
    fn glyph_bits_fit_their_width() {
        for c in "0123456789hms:".chars() {
            let g = glyph(c).unwrap_or_else(|| unreachable!());
            assert!(
                g.rows.iter().all(|&row| u32::from(row) < (1 << g.width)),
                "{c:?} overflows"
            );
        }
    }

    #[test]
    fn measures_text() {
        assert_eq!(text_width("23m"), 5 * 3 + 2);
        assert_eq!(text_width("1:23"), 5 * 3 + 1 + 3);
        assert_eq!(text_width(""), 0);
    }
}
