# CraftProfit and Price

World of Warcraft addon for:

- manual Auction House full-price scans
- tooltip price display
- profession crafting cost / profit display

## Current scope

- Manual scan button in the Auction House
- Latest scan replaces older stored prices
- Tooltip shows total value by default
- Holding `Shift`, `Alt`, or `Ctrl` shows unit price
- Profession list shows profit in gold
- Profession detail shows sale price, auction fee, material cost, net profit, and margin
- If an item has no Auction House price, only total material cost is shown in gray

## Install

Copy this folder into:

`World of Warcraft/_retail_/Interface/AddOns/`

The addon folder name should stay aligned with the `.toc` file setup.

## Slash commands

- `/cp scan`
- `/cp status`
- `/cp wipe`

## Notes

- This addon uses Blizzard UI APIs only.
- Auction House scanning is manual, not automatic.
- No third-party code or assets are bundled from `RECrystallize`.

## License

This project is released under the MIT License.
See [LICENSE](LICENSE).
