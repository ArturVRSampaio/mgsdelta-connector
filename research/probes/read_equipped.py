"""
Read-only probe: what does the equipped-camo/facepaint main-pointer chain
currently report? Run this and compare against what's actually visible on
the character in-game, to figure out whether the byte is a global item
index or a local camo/facepaint-only index, before writing anything.
"""

from mgs_memory import MGSMemory, load_index


def main() -> None:
    mem = MGSMemory()
    weapons, items = load_index()

    camo = mem.read_equipped_camo()
    facepaint = mem.read_equipped_facepaint()
    weapon = mem.read_equipped_weapon()
    item = mem.read_equipped_item()

    print(f"Raw equipped_camo byte = {camo}")
    print(f"Raw equipped_facepaint byte = {facepaint}")
    print(f"Raw equipped_weapon byte = {weapon}")
    print(f"Raw equipped_item byte = {item}")

    camo_items = [i for i in items if 50 <= i.index <= 103]
    facepaint_items = [i for i in items if 116 <= i.index <= 138]

    def _lookup(entries: list, index: int) -> str:
        match = next((e for e in entries if e.index == index), None)
        return match.name if match else "(out of range)"

    print()
    print(f"If global item index: camo={_lookup(items, camo)} facepaint={_lookup(items, facepaint)}")
    if camo < len(camo_items):
        print(f"If local camo-group index: camo={camo_items[camo].name}")
    if facepaint < len(facepaint_items):
        print(f"If local facepaint-group index: facepaint={facepaint_items[facepaint].name}")
    if weapon < len(weapons):
        print(f"If weapon index matches directly: weapon={weapons[weapon].name}")


if __name__ == "__main__":
    main()
