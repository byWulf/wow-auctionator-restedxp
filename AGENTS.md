# AGENTS.md

## Language

All documentation in this repository (README, AGENTS.md, code comments, commit messages) is written in **English**.

## Project

WoW addon `AuctionatorRestedXP`: fills the Auctionator shopping list `RestedXP` with the items the current RestedXP guide wants you to buy at the auction house, with the missing quantity.

- `AuctionatorRestedXP.toc`: addon manifest, interface `16001` (WoW Forever only, Classic Era is not supported), depends on `Auctionator`
- `AuctionatorRestedXP.lua`:
  - Reads the parsed guide from RestedXP's global `RXP` (`RXP.currentGuide.steps[i]`), the current step from `RXPCData.currentStep` and skipped steps from `RXPCData.stepSkip`, like `wow-arkinventory-rules-restedxp`. The next guide is resolved and parsed the same way (`NEXT_GUIDES`).
  - An auction house purchase is a step with `step.ah` (guide tag `#ah`), a `target` element whose `targets` contain "Auctioneer" and `collect` elements (`element.id`, `element.qty`). `#ah` alone is not enough: it only means "hidden in Solo Self Found mode" (`RXP.stepLogic.AHCheck`) and is also used for looting, vendor and mailbox steps. The guides keep English NPC names in `.target` even in translated (e.g. deDE) guides. This was checked against all imported WoW Forever guides (140 matching steps).
  - Steps are filtered with `RXP.IsStepShown(step, guide)`. For the active step `element.numRequired` (maintained by RestedXP) is used instead of `element.qty`. Elements whose `questId` is turned in are skipped unless `ignoreTurnIn`. Per item the maximum quantity wins, then `GetItemCount(id, true)` (bags + bank) is subtracted.
  - Writes the list with `Auctionator.API.v1.ConvertToSearchString` (`isExact`, `quantity`) and `Auctionator.API.v1.CreateShoppingList`, which replaces an existing list. Item names are loaded with `Item:ContinueOnItemLoad` first.
  - Updates on `AUCTION_HOUSE_SHOW` (delayed so Auctionator's tabs exist) and, while the auction house is open, when the guide or step changes (2 second ticker). Unchanged results are not written again unless the list was deleted. `/arxp` forces an update.
- `README.md`: user documentation, keep it in sync with the detection rules

## Installed copies

The addon is installed as a plain copy (not a clone) in:

- `C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\AuctionatorRestedXP`

After changing the `.toc` or `.lua`, copy them there. The folder name must stay `AuctionatorRestedXP`.

## Testing

There is no automated test setup. Changes are verified in game with `/reload`, opening the auction house and `/arxp`.

## Releasing

Not published yet. Once a CurseForge project exists, add `## X-Curse-Project-ID` to the TOC and the CurseForge link to the README. Releases are built by `.github/workflows/release.yml` with the BigWigs packager (`.pkgmeta` sets the folder name and leaves out `AGENTS.md`/`CLAUDE.md`):

1. Commit and push the changes to `main`.
2. Tag and push: `git tag -a vX.Y.Z -m "X.Y.Z"` and `git push origin vX.Y.Z` (semantic versioning).
3. The workflow packages the addon, replaces `@project-version@` in the TOC with the tag, uploads the zip to CurseForge (game version from the TOC interface, WoW Forever) and creates the GitHub release. The changelog is generated from the commit messages since the previous tag.

The CurseForge upload needs the repository secret `CF_API_TOKEN` (a CurseForge author API token). "Run workflow" on the Actions tab builds the package as an artifact without uploading. Never edit `## Version` in the TOC by hand; installed dev copies show `@project-version@`.
