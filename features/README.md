# Writ feature map

`features.json` is the executable inventory. The check fails when a mapped accessibility identifier or page marker disappears; `tools/live` walks it before checking the deployed site.

| Surface | Reach it through | Proof |
|---|---|---|
| Enforcement | The header switch | Accessibility identifier `writ.enforcing`; the value says On or Off. |
| Input and Output | The two direction tabs | `writ.direction.input` and `.output`; the selected tab exposes the current device, volume and priority list. |
| Mute and level | Current-device card | `writ.mute.<direction>` and the labelled Input level meter. |
| Device choice and order | A device row, its grip, or Options | Dynamic `writ.device.<direction>.<uid>` and `writ.device-options…`; click selects, drag reorders, Move to Top is the accessible equivalent. |
| Device rules and label | The row’s Options menu | Never/allow, lid rule, Icon & Label, Move to Top and Forget Device live behind the mapped options control. |
| Settings | Gear | `writ.settings` opens the mapped login, restore, shortcut, update, support and version items. |
| Keyboard shortcuts | Settings → Keyboard Shortcuts | Each action is `writ.shortcuts.action.<action>`; Restore Defaults is separately mapped. |
| Quit | Panel footer | `writ.quit`. |
| Website | `writ.braininavat.dance` | Home, Privacy and Licence pages are mapped; `tools/live site` also checks their links/assets, appcast and versioned DMG. |

The verification skill launches the local build with `--preview`, which owns one ordinary Writ window and no menu-bar item. It inspects the accessibility tree, exercises Input/Output and Settings without changing devices or saved order, captures evidence, then terminates only that process. Update both map files whenever a menu item, setting, site page or accessibility identifier changes.
