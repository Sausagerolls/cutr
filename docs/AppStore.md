# App Store Connect metadata

## App Information
- **Name:** Cutr
- **Subtitle (30):** Sheet cutting optimiser
- **Primary category:** Productivity
- **Secondary category:** Utilities
- **Content rights:** No third-party content
- **Age rating:** answer "None" to everything (4+)

## Pricing
Free (or your choice).

## App Privacy
- **Privacy policy URL:** https://github.com/Sausagerolls/cutr/blob/main/PRIVACY.md
- **Data collection:** "No, we do not collect data from this app". Cut lists sync through the user's own iCloud account, which Apple does not count as collection by the developer.

## Version 1.0
**Promotional text (170):**
Plan every cut before you pick up the saw. Cutr packs your parts onto sheets of plywood or MDF with the least waste, then prints a clean cut sheet.

**Description:**
Cutr works out the most efficient way to cut your parts from sheets of plywood, MDF, melamine or any other board.

Enter your sheet sizes and the parts you need, and Cutr lays them out in about a second, leaving a gap for the saw blade between every part.

FEATURES
• Fast layout optimiser that minimises sheets and waste
• Settable kerf / buffer between parts and edge trim around each sheet
• Grain direction lock for parts that must not rotate
• Multiple sheet stock types in one cut list, with quantities and prices
• Cost, sheet count and waste statistics
• Custom part shapes: pull points out of an edge to make gables, points, chamfers and triangles, with snapping and alignment guides
• Group cut lists into projects
• Save, name, search and sort cut lists by name or date
• Millimetres, centimetres or inches, including fractions such as 23 7/16
• Export a PDF cut sheet or print it directly
• iCloud sync between iPhone and iPad
• No account, no ads, no tracking

Cutr is open source: https://github.com/Sausagerolls/cutr

**Keywords (100):**
cut list,plywood,sheet,optimizer,woodworking,cutting,mdf,panel,saw,layout,carpentry,diy,kerf,board

**Support URL:** https://github.com/Sausagerolls/cutr/issues
**Marketing URL:** https://github.com/Sausagerolls/cutr
**Copyright:** 2026 Jake Watts

## Screenshots
- iPhone 6.9": `docs/screenshots/iphone-*.png` (1320 × 2868)
- iPad 13": `docs/screenshots/ipad-*.png` (2064 × 2752)

## App Review notes
No sign-in required. Tap + to create a cut list, add a sheet, then add parts. The layout updates automatically.

## Export compliance
`ITSAppUsesNonExemptEncryption` is false in Info.plist, so no questions appear.

## Before submitting
Deploy the CloudKit schema to production: CloudKit Console, container iCloud.com.jakewatts.cutr, Schema, "Deploy Schema Changes". Without this, sync fails in the App Store build.
