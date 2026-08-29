"""Generate the sixteen-colour HUD marker font used by the input data pack."""

from pathlib import Path

from PIL import Image


GLYPH_SIZE = 64
GLYPH_COUNT = 16


def marker_colour(code: int) -> tuple[int, int, int, int]:
    return 250, 16 + code * 14, 246, 255


def main() -> None:
    project = Path(__file__).resolve().parents[1]
    output = project / "assets" / "mcrv" / "textures" / "font" / "input.png"
    output.parent.mkdir(parents=True, exist_ok=True)
    image = Image.new("RGBA", (GLYPH_SIZE * GLYPH_COUNT, GLYPH_SIZE))
    for code in range(GLYPH_COUNT):
        colour = marker_colour(code)
        for x in range(code * GLYPH_SIZE, (code + 1) * GLYPH_SIZE):
            for y in range(GLYPH_SIZE):
                image.putpixel((x, y), colour)
    image.save(output, optimize=True)
    print(output)


if __name__ == "__main__":
    main()
