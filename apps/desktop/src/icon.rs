//! Tray icons, drawn in code: a crescent when there is no countdown, otherwise a
//! coloured badge with the time left (`23m`, `1:23`, `45s`) in a pixel font.

use crate::font;

/// Rendered at twice the usual 22-pixel tray size so it stays sharp on HiDPI panels.
pub const SIZE: u32 = 44;

/// An RGBA image, row-major, 4 bytes per pixel.
pub struct Image {
    pub size: u32,
    pub rgba: Vec<u8>,
}

/// Badge colours: emerald while waiting for the adhan, amber while waiting for the iqama.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Tone {
    Adhan,
    Iqama,
}

impl Tone {
    fn color(self) -> [u8; 3] {
        match self {
            Tone::Adhan => [0x0D, 0x8F, 0x78],
            Tone::Iqama => [0xE0, 0x7B, 0x1A],
        }
    }
}

/// A light crescent moon on a transparent background.
pub fn crescent() -> Image {
    let s = SIZE as f32;
    let (outer_x, outer_y, outer_r) = (s * 0.48, s * 0.5, s * 0.38);
    let (cut_x, cut_y, cut_r) = (s * 0.64, s * 0.38, s * 0.32);
    render(|px, py| {
        let in_outer = (px - outer_x).powi(2) + (py - outer_y).powi(2) <= outer_r.powi(2);
        let in_cut = (px - cut_x).powi(2) + (py - cut_y).powi(2) <= cut_r.powi(2);
        (in_outer && !in_cut).then_some([0xEE, 0xEE, 0xEE])
    })
}

/// A rounded badge in `tone` with `text` centred in white, scaled as large as fits.
pub fn badge(text: &str, tone: Tone) -> Image {
    let s = SIZE as f32;
    let radius = s * 0.22;
    let color = tone.color();

    // Largest whole-pixel scale at which the text fits with a small margin.
    let width = font::text_width(text).max(1);
    let scale = (1..=4)
        .rev()
        .find(|&k| width * k <= SIZE - 6 && font::HEIGHT * k <= SIZE - 6)
        .unwrap_or(1);
    let (text_w, text_h) = (width * scale, font::HEIGHT * scale);
    let origin_x = (SIZE - text_w) / 2;
    let origin_y = (SIZE - text_h) / 2;
    let text_pixels = rasterize(text, scale);

    let mut image = render(|px, py| {
        // Rounded rectangle covering the whole icon.
        let dx = (radius - px).max(px - (s - radius)).max(0.0);
        let dy = (radius - py).max(py - (s - radius)).max(0.0);
        (dx * dx + dy * dy <= radius * radius).then_some(color)
    });

    // Text is pixel-aligned (no antialiasing) so the pixel font stays crisp.
    for (x, y) in text_pixels {
        let (x, y) = (origin_x + x, origin_y + y);
        if x < SIZE && y < SIZE {
            let i = ((y * SIZE + x) * 4) as usize;
            if let Some(pixel) = image.rgba.get_mut(i..i + 4) {
                pixel.copy_from_slice(&[0xFF, 0xFF, 0xFF, 0xFF]);
            }
        }
    }
    image
}

/// The lit pixels of `text` at `scale`, relative to its top-left corner.
fn rasterize(text: &str, scale: u32) -> Vec<(u32, u32)> {
    let mut pixels = Vec::new();
    let mut pen = 0;
    for glyph in text.chars().filter_map(font::glyph) {
        for (row, bits) in glyph.rows.iter().enumerate() {
            for col in 0..glyph.width {
                if bits & (1 << (glyph.width - 1 - col)) != 0 {
                    for sy in 0..scale {
                        for sx in 0..scale {
                            pixels.push(((pen + col) * scale + sx, row as u32 * scale + sy));
                        }
                    }
                }
            }
        }
        pen += glyph.width + 1;
    }
    pixels
}

/// Draws a shape given as "colour at this point, if inside", with 4×4 supersampling.
fn render(shape: impl Fn(f32, f32) -> Option<[u8; 3]>) -> Image {
    let mut rgba = Vec::with_capacity((SIZE * SIZE * 4) as usize);
    for y in 0..SIZE {
        for x in 0..SIZE {
            let mut covered = 0u32;
            let mut color = [0u8; 3];
            for sy in 0..4 {
                for sx in 0..4 {
                    let px = x as f32 + (sx as f32 + 0.5) / 4.0;
                    let py = y as f32 + (sy as f32 + 0.5) / 4.0;
                    if let Some(c) = shape(px, py) {
                        covered += 1;
                        color = c;
                    }
                }
            }
            rgba.extend_from_slice(&[color[0], color[1], color[2], (covered * 255 / 16) as u8]);
        }
    }
    Image { size: SIZE, rgba }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn pixel(image: &Image, x: u32, y: u32) -> [u8; 4] {
        let i = ((y * image.size + x) * 4) as usize;
        [
            image.rgba[i],
            image.rgba[i + 1],
            image.rgba[i + 2],
            image.rgba[i + 3],
        ]
    }

    #[test]
    fn images_have_the_expected_size() {
        assert_eq!(crescent().rgba.len(), (SIZE * SIZE * 4) as usize);
        assert_eq!(
            badge("23m", Tone::Adhan).rgba.len(),
            (SIZE * SIZE * 4) as usize
        );
    }

    #[test]
    fn badge_has_transparent_corners_and_a_coloured_body() {
        let image = badge("9m", Tone::Adhan);
        assert_eq!(pixel(&image, 0, 0)[3], 0, "corner should be transparent");
        assert_eq!(pixel(&image, 2, SIZE / 2), [0x0D, 0x8F, 0x78, 0xFF]);
        assert_eq!(
            pixel(&badge("9m", Tone::Iqama), 2, SIZE / 2),
            [0xE0, 0x7B, 0x1A, 0xFF]
        );
    }

    #[test]
    fn text_is_drawn_in_white() {
        let white = |image: &Image| {
            image
                .rgba
                .chunks(4)
                .filter(|p| p == &[0xFF, 0xFF, 0xFF, 0xFF])
                .count()
        };
        assert!(white(&badge("23m", Tone::Adhan)) > 50);
        assert!(white(&badge("1:23", Tone::Adhan)) > 50);
        // Different text, different pixels.
        assert_ne!(
            badge("23m", Tone::Adhan).rgba,
            badge("24m", Tone::Adhan).rgba
        );
    }

    #[test]
    fn short_text_is_drawn_larger() {
        let lit = |text: &str| rasterize(text, 1).len();
        let white = |image: &Image| {
            image
                .rgba
                .chunks(4)
                .filter(|p| p == &[0xFF, 0xFF, 0xFF, 0xFF])
                .count()
        };
        // "9m" fits at a larger scale than "23m": more white pixels per font pixel.
        assert!(
            white(&badge("9m", Tone::Adhan)) / lit("9m")
                > white(&badge("23m", Tone::Adhan)) / lit("23m")
        );
    }
}
