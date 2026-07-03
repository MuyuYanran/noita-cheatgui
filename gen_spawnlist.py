# =============================================================================
# gen_spawnlist.py - 自动生成 spawnables.lua 的脚本
# =============================================================================
# 扫描解包后的 Noita 数据文件中的物品 XML，提取物品名称并生成
# spawnables.lua 的可生成实体列表。
# 
# 用法：
#   python gen_spawnlist.py [Noita 数据目录路径]
#   默认路径：%LOCALAPPDATA%/../LocalLow/Nolla_Games_Noita/data
# =============================================================================

import os
import sys
import re

# 匹配 item_name 属性的正则（不用 XML 库，因为 Noita 的 XML 不标准）
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
    """向物品列表添加一个物品条目"""
    # 仅处理 XML 文件
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
    """递归扫描目录，收集所有物品的 (路径, 名称, 原始文件名) 三元组"""
    all_items = []
    for root, _, files in os.walk(rootdir):
        for fname in files:
            fullpath = os.path.join(root, fname)
            subpath = prefix + fullpath.replace(rootdir, "").replace("\\", "/")
            add_item(all_items, fullpath, subpath)
    return all_items

def escape_quotes(s):
    """转义单引号（防止 Lua 字符串解析出错）"""
    return s.replace("'", "\\'")

def item_to_lua(item):
    """将物品三元组转换为 Lua 表字面量"""
    return f"{{path='{escape_quotes(item[0])}', name='{escape_quotes(item[1])}', xml='{item[2]}'}}"

def item_list_to_lua(item_list):
    """将物品列表转换为完整的 spawn_list Lua 代码"""
    body = ",\n  ".join(item_to_lua(item) for item in item_list)
    return "spawn_list = {\n  " + body + "\n}"

if __name__ == "__main__":
    # 获取 Noita 数据目录（可通过命令行参数指定）
    if len(sys.argv) >= 2:
        path = sys.argv[1]
    else:
        path = os.path.abspath(os.path.expandvars(r'%LOCALAPPDATA%/../LocalLow/Nolla_Games_Noita/data'))
    print("Using path to Noita data: ", path)
    items_path = os.path.join(path, "entities/items")
    print("Path to items: ", items_path)
    items = find_items(items_path, "data/entities/items")
    items = sorted(items)  # 按路径排序，便于 diff
    print(f"Found {len(items)} items.")
    lua = """
-- 自动生成！请勿直接编辑！
-- 运行 'gen_spawnlist.py' 重新生成！（需要解包后的数据！）
-- 请手动将特殊物品添加到 'special_spawnables.lua' 中！
""" + item_list_to_lua(items)
    with open("data/hax/spawnables.lua", "wt") as dest:
        dest.write(lua)