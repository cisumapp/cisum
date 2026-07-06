# FEEDBACK

Reviewer / user feedback captured for future work.

## Now Playing UI (TestFlight review)

- [ ] Volume slider: reduce horizontal width and make it thinner — `Modules/Features/Player/Sources/Player/UI/Components/Slider/VolumeSlider.swift`
- [ ] Now-playing title/artist text: slightly less bold — `NowPlayingComponents.swift:103` (title) & `:118` (artist), `.fontWeight(.semibold)` → `.medium`/`.regular`
- [ ] Volume-row icons: lighter color when ACTIVE vs inactive (state-based tint in `NowPlayingFooter`; currently uniform white 0.8)
- [ ] Reviewer note re: "languages — the main ones" — context unclear, clarify what was meant before acting
