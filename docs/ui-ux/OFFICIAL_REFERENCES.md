# Official UI/UX Reference Routes

These are starting points, not frozen truth. Verify current pages and the project's
pinned framework/SDK version during research. Last route audit: 2026-08-08.

## Apple platforms and SwiftUI

- [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)
- [Apple layout guidance](https://developer.apple.com/design/human-interface-guidelines/layout)
- [Apple accessibility guidance](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- [Performing accessibility testing](https://developer.apple.com/documentation/accessibility/performing-accessibility-testing-for-your-app)
- [SwiftUI accessibility fundamentals](https://developer.apple.com/documentation/swiftui/accessibility-fundamentals)
- [Creating an Audio Unit extension](https://developer.apple.com/documentation/avfaudio/creating-an-audio-unit-extension)
- [Incorporating audio effects and instruments](https://developer.apple.com/documentation/audiotoolbox/incorporating-audio-effects-and-instruments)

Apple currently recommends adaptive layouts that handle device/window variation,
Dynamic Type and locale changes. Its accessibility guidance requires testing with
assistive technologies rather than relying on labels alone and provides platform
target-size guidance. Recheck exact numbers and APIs before encoding them as tokens.

## JUCE

- [JUCE Component reference](https://docs.juce.com/master/classjuce_1_1Component.html)
- [JUCE AccessibilityHandler reference](https://docs.juce.com/master/classjuce_1_1AccessibilityHandler.html)
- [JUCE AudioProcessorEditor reference](https://docs.juce.com/master/classjuce_1_1AudioProcessorEditor.html)
- [JUCE AudioProcessorValueTreeState attachments](https://docs.juce.com/master/classjuce_1_1AudioProcessorValueTreeState_1_1SliderAttachment.html)

JUCE exposes explicit keyboard focus traversal, accessibility handlers/events,
host-resizable editor constraints, and lifetime-sensitive parameter attachments. Verify
behavior against the pinned JUCE commit and actual target hosts.

## VST3

- [VST3 technical documentation](https://steinbergmedia.github.io/vst3_dev_portal/pages/Technical%2BDocumentation/Index.html)
- [VST3 host parameter context menus](https://steinbergmedia.github.io/vst3_dev_portal/pages/Technical%2BDocumentation/Change%2BHistory/3.5.0/IComponentHandler3.html)

VST3 hosts may communicate content scale, automation state, and parameter-specific
context-menu functions. Treat them as host contracts, not optional decoration, when the
shipped format and supported hosts expose them.
