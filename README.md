# Auctionator RestedXP Shopping List

Fills an [Auctionator](https://www.curseforge.com/wow/addons/auctionator) shopping list with the items your [RestedXP](https://www.restedxp.com/) guide wants you to buy at the auction house, in the quantity you still need.

When you open the auction house, the addon looks at the remaining steps of your current RestedXP guide and the guide after it, collects every item the guide tells you to buy from an auctioneer, subtracts what is already in your bags and bank, and writes the result into the Auctionator shopping list **RestedXP** (Shopping tab). Each entry is an exact name search with the purchase quantity set.

## Supported game versions

| Version | Interface |
|---|---|
| WoW Forever | 16001 |

Classic Era and other versions are not supported.

## Requirements

- Auctionator
- RestedXP Guides with a guide loaded

## Installation

Install it from CurseForge, e.g. with the CurseForge app.

For a manual installation, note that the folder in your AddOns directory **must** be named `AuctionatorRestedXP`, otherwise WoW will not load the addon:

```bash
cd "C:/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns"
git clone https://github.com/byWulf/wow-auctionator-restedxp.git AuctionatorRestedXP
```

Alternatively, download the ZIP from the [releases](https://github.com/byWulf/wow-auctionator-restedxp/releases) and extract it into `Interface/AddOns`.

Then `/reload` in game.

## Usage

Just open the auction house. The list **RestedXP** is updated and Auctionator opens it in the Shopping tab; a chat message lists the items. While the auction house is open, the list is updated again whenever the guide moves to another step.

`/arxp` (or `/auctionatorrestedxp`) updates the list right away and prints it, e.g. after you skipped a step.

## Which items count

A guide step counts as an auction house purchase when it

- is marked as an auction house step in the guide (`#ah`, hidden by RestedXP in Solo Self Found mode),
- targets an auctioneer (`.target Auctioneer …`), and
- asks you to collect items (`.collect itemID,quantity`).

From these steps the addon takes

- the current step and all following steps of the loaded guide, plus earlier steps that are still active, leaving out steps you skipped,
- all steps of the next guide (`#next`),
- only steps RestedXP would show for your character (class, season, phase, dungeon and other step filters),
- per item the largest quantity of any of these steps, minus the items in your bags and bank. Items whose quest is already turned in are left out. For the active step, quest objectives you already completed are subtracted, like RestedXP does.

If Solo Self Found is enabled in RestedXP, the list stays empty.

## Limitations

- Steps that only mention the auction house in their text (e.g. "you can also buy these at the auction house") without targeting an auctioneer are not included.
- Items that are still in your mailbox are not counted as owned.
- The list is replaced on every update, so don't put your own items into the list **RestedXP**.
- The list is not updated after each single purchase, only when the guide step changes or when you run `/arxp`.

## License

[MIT](LICENSE)
