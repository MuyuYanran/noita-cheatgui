import os
import sys
import re

ITEM_NAME_PATT = re.compile(r'item_name\s*=\s*"([^"]*)"')

def find_item_name(raw_xml):
    """从 XML 中查找 `item_name`

    我们不使用真正的 XML 库，因为 Noita 的 XML 文件是非标准的。
    所以直接像天真的计算机学生一样用正则搜索这个键值对。
    """
    match = ITEM_NAME_PATT.search(raw_xml)
    if match is None:
        return None
    return match.groups()[0]

def add_item(item_list, filename, subpath):
    # 假设所有可生成物都是 XML 文件
    if filename[-4:].lower() != ".xml":
        return
    with open(filename, "rt") as src:
        data = src.read()
    ui_name = find_item_name(data)
    raw_name = os.path.split(filename)[-1]
    if ui_name is None:
        ui_name = raw_name
    item_list.append((subpath, ui_name, raw_name))

def find_items(rootdir, prefix=""):
    all_items = []
    for root, _, files in os.walk(rootdir):
        for fname in files:
            fullpath = os.path.join(root, fname)
            subpath = prefix + fullpath.replace(rootdir, "").replace("\\", "/")
            add_item(all_items, fullpath, subpath)
    return all_items

def escape_quotes(s):
    """转义单引号

    我不确定 Noita 的物品名称是否真的会用到单引号，但谨慎一点总没错。
    """
    return s.replace("'", "\\'")

def item_to_lua(item):
    return f"{{path='{escape_quotes(item[0])}', name='{escape_quotes(item[1])}', xml='{item[2]}'}}"

def item_list_to_lua(item_list):
    body = ",\n  ".join(item_to_lua(item) for item in item_list)
    return "spawn_list = {\n  " + body + "\n}"

if __name__ == "__main__":
    if len(sys.argv) >= 2:
        path = sys.argv[1]
    else:
        path = os.path.abspath(os.path.expandvars(r'%LOCALAPPDATA%/../LocalLow/Nolla_Games_Noita/data'))
    print("Using path to Noita data: ", path)
    items_path = os.path.join(path, "entities/items")
    print("Path to items: ", items_path)
    items = find_items(items_path, "data/entities/items")
    items = sorted(items) # 按路径排序
    print(f"Found {len(items)} items.")
    lua = """
-- 自动生成！请勿直接编辑！
-- 运行 'gen_spawnlist.py' 重新生成！（需要解包后的数据！）
-- 请手动将特殊物品添加到 'special_spawnables.lua' 中！
""" + item_list_to_lua(items)
    with open("data/hax/spawnables.lua", "wt") as dest:
        dest.write(lua)