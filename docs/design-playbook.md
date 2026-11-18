# Reasi design playbook

How Reasi should look and why. Written 12 Nov 2026 from Apple's own guidance for iOS 26, then applied to the app. Revised 17 Nov 2026 after studying the ElevenLabs iPhone app as a reference for a calm, monochrome interface: one sans-serif family, a solid main button, and soft grey cards on a white page. Sources are at the end.

## The idea in one line

A white page, soft grey cards, one black button. Navigation floats above in glass. Size and weight do the work that boxes, colours and captions used to do.

## 1. Two layers

Apple splits an interface into a **content layer** (your lists, numbers, photos) and a **functional layer** (navigation and controls) that floats above it in Liquid Glass.

- **Glass is for navigation and floating controls only.** Tab bar, top bar buttons, the + button, the List dock, sheets and menus. The main action button is not glass: see section 3.
- **Never glass in the content layer.** List rows, cards, totals, charts and backgrounds stay flat. Apple's wording: "Don't use Liquid Glass in the content layer."
- **Use it sparingly.** Limit custom glass to "the most important functional elements". One glass group per screen edge is plenty.
- **Don't stack glass on glass**, and don't crowd glass controls together.
- **Regular glass, not clear.** Clear glass is only for controls sitting on photos or video.
- **No custom backgrounds on bars.** Let content scroll beneath controls; the system's scroll edge effect keeps them legible. A bar with an opaque fill fights that.
- **Prefer system pieces.** `TabView`, toolbars, `.buttonStyle(.glass)` / `.glassProminent`, system sheets and confirmation dialogs pick up glass on their own. Reach for `glassEffect` only for a control the system doesn't have, and put neighbours in one `GlassEffectContainer`.
- **Concentric shapes.** Controls near the screen edge are capsules or circles, matching the tab bar and the device corners.
- **No tinted glass.** Glass stays neutral. Emphasis comes from the solid main button, not from colour in glass.

## 2. Type

- **One family: San Francisco.** Display text (screen titles, section headings, dish names and big money figures) is set apart by size and a medium weight, not by a second typeface. It matches the text inside system controls and follows Dynamic Type and Bold Text without extra work.
- **Why not a custom face.** Inter is the default face of generated interfaces, so it reads as generic the moment the app opens, and any bundled face sits beside the system's own in bars and menus. The 12 Nov version used New York (serif) for display; it was dropped on 17 Nov so the whole app speaks in one voice.
- **Hierarchy comes from size and weight, not from capitals or colour.** No all-caps labels. Sentence case everywhere.
- **Apple's text styles only.** Large title 34, title 28, title 2 at 22, title 3 at 20, headline 17 semibold, body 17, callout 16 (Reasi's everyday reading size), subheadline 15, footnote 13, caption 12, caption 2 at 11. No text below 11.
- **Weights: regular, medium, semibold.** No light weights. Display text is medium. Secondary text is regular in a muted colour, not semibold and small. Small symbols (ticks, chevrons) may be bold so they stay crisp; that is icon weight, not type.
- **Numbers line up.** Money uses monospaced digits wherever figures stack or change.

## 3. Minimal, concretely

- **One idea per screen region.** A number, what it's of, and at most one short line. Explanations live behind ⓘ or a tap.
- **Fewer boxes.** Group with spacing and hairlines before reaching for a card. A screen should not be a stack of identical rectangles.
- **Cards are a soft grey fill on a white page.** No border, no shadow. In dark mode the page is near-black and cards are one step lighter. An outline appears only to mark the selected option in a set.
- **One main action per screen, as a solid capsule.** Ink colour with the page colour for its label: black on white, white on dark. Secondary actions are quiet grey capsules of the same shape.
- **Chips are small grey capsules.** A selected chip inverts, like the main button. A chip's label is one line at ordinary text sizes and wraps at accessibility sizes, where rows of chips also stack vertically.
- **Section labels are small and muted**, with at most one quiet action on the right ("See plan"). Larger section headings are medium weight, never bold.
- **Photos where the data has them**, quiet symbols where it doesn't. Never an empty frame.
- **Black, white and greys.** Green only for "ticked", amber only for a warning.
- **Motion is the system's.** Glass morphs, sheets and tab changes come from the system; Reasi adds haptics, not animation flourishes.

## 4. Checklist for any new screen

1. Is anything in the content drawn in glass? Remove it.
2. Does every floating control use a system style, or share one glass container?
3. Is there an opaque bar hiding content that could scroll beneath it?
4. Is all type San Francisco in a built-in text style, with display text in medium weight?
5. Any capitals, exclamation marks, or sentences explaining the obvious? Cut them.
6. Could two cards be one list?
7. Is there exactly one solid main button, and does any card have a border it doesn't need?

## Sources

- [Human Interface Guidelines: Materials](https://developer.apple.com/design/human-interface-guidelines/materials)
- [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)
- [Human Interface Guidelines: Typography](https://developer.apple.com/design/human-interface-guidelines/typography)
- [WWDC25: Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/)
- [WWDC25: Get to know the new design system](https://developer.apple.com/videos/play/wwdc2025/356/)
- [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views)
