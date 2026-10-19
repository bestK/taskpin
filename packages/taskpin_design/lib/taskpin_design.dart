// TaskPin Design System (Windows 11 native, docs/VISUAL_SPEC.md).
//
// The single import for app code:
//
//   import 'package:taskpin_design/taskpin_design.dart';
//
// Contents:
//   - the three-layer token system (primitives -> semantic -> component)
//   - `TaskPinTheme`, a ThemeExtension exposing tokens to widgets
//   - the component library
//   - the debug-only gallery route widget
//
// Design rules this package exists to enforce:
//
//   1. Dark-first, calm, high-signal. A monitoring tool should look like an
//      instrument panel, not a document.
//   2. ONE accent (iris). Semantic colour is for STATE only, never decoration.
//   3. Metrics use tabular figures, always. Use `TpMetric` for any number.
//   4. Widgets never name a colour. Read it from `TaskPinTheme.of(context)`.
//      Enforced by test/no_raw_colors_test.dart.
//   5. Every interactive component is keyboard-focusable and draws a 2 px
//      focus ring. This is new capability — the ImGui and Win32 UIs it
//      replaces had no keyboard focus story at all.
//
// The bar token list (`TpBarColors`, `TpBarMetrics`) is FROZEN: it is
// duplicated in C++ and Swift. See the banner in `src/tokens/bar_tokens.dart`.

library;

// Tokens
export 'src/tokens/bar_tokens.dart';
export 'src/tokens/elevation.dart';
export 'src/tokens/motion.dart';
export 'src/tokens/primitives.dart';
export 'src/tokens/radius.dart';
export 'src/tokens/semantic.dart';
export 'src/tokens/spacing.dart';
export 'src/tokens/typography.dart';

// Theme
export 'src/theme/taskpin_theme.dart';

// Models
export 'src/models/bar_span.dart';
export 'src/models/param_decl.dart';

// Utilities
export 'src/util/avatar_color.dart';
export 'src/util/color_hex.dart';
export 'src/util/focus.dart';

// Components
export 'src/components/bar.dart';
export 'src/components/code.dart';
export 'src/components/data.dart';
export 'src/components/feedback.dart';
export 'src/components/forms.dart';
export 'src/components/list.dart';
export 'src/components/settings.dart';
export 'src/components/shell.dart';
export 'src/components/status.dart';
export 'src/components/ui.dart';

// Gallery
export 'src/gallery/gallery.dart';
