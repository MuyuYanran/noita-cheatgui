-- i18n.lua - Language / translations configuration for cheatgui
-- Set _i18n.language to "zh" for Chinese, "en" for English (default)
-- Add more languages by inserting a new table under _i18n.translations

_i18n = {
    language = "zh",  -- "en" | "zh"

    translations = {
        en = {
            -- ====== Shared / General ======
            yes = "Yes",
            no = "No",
            none = "None",

            -- ====== Panel names ======
            panel_closed = "[+]",
            panel_wand_builder = "wand builder",
            panel_teleport = "teleport",
            panel_health = "health",
            panel_gold = "gold",
            panel_spells = "spells",
            panel_perks = "perks",
            panel_flasks = "flasks",
            panel_wands = "wands",
            panel_items = "items",
            panel_widgets = "widgets",
            panel_fungal = "fungal",
            panel_console = "console",
            panel_gui_grid_ref = "gui grid ref.",
            panel_always_cast = "always cast",
            panel_shift_material = "shift material",
            panel_settings = "settings",

            -- ====== Breadcrumbs ======
            back = "< back",

            -- ====== Filter / Sort ======
            filter_label = "Filter:",
            filter_placeholder = "[shift+type to filter]",
            alphabetize = "Alphabetize:",
            show_localized_names = "Show localized names:",

            -- ====== Page navigation ======
            page_prev_arrow = "<-",
            page_next_arrow = "->",

            -- ====== Wand Builder ======
            wb_shuffle = "Shuffle",
            wb_mana = "Mana",
            wb_mana_recharge = "Mana Recharge",
            wb_slots = "Slots",
            wb_multicast = "Multicast",
            wb_reload = "Reload",
            wb_delay = "Delay",
            wb_spread = "Spread",
            wb_speed = "Speed",
            wb_always_cast = "Always cast",
            wb_always_cast_n = "Always cast (%d)",
            wb_none = "None",
            wb_reset_all = "[Reset all]",
            wb_spawn_wand = "[Spawn]",

            -- ====== Teleport ======
            tp_x = "X",
            tp_y = "Y",
            tp_get_pos = "[Get current position]",
            tp_zero_pos = "[Zero position]",
            tp_teleport = "[Teleport]",
            tp_log_teleport = "Attempting to teleport to (%d, %d)",
            tp_separator = "---- Quick Teleports ----",
            tp_quick_teleport_format = "%s (%d, %d)",

            -- ====== Health ======
            hp_hp = "HP",
            hp_max_hp = "Max HP",
            hp_get = "[Get current health]",
            hp_apply = "[Apply health changes]",
            hp_separator = "---- Quick Health ----",
            hp_add_25 = "[Add +25 max HP]",
            hp_add_100 = "[Add +100 max HP]",

            -- ====== Gold ======
            gold_label = "Gold",
            gold_get = "[Get current gold]",
            gold_set = "[Set current gold]",
            gold_separator = "---- Quick Gold ----",
            gold_add_100 = "[+100 Gold]",
            gold_add_500 = "[+500 Gold]",
            gold_add_2000 = "[+2000 Gold]",

            -- ====== Flasks / Potions ======
            flask_quantity = "Quantity mult:",
            flask_container = "Container:",
            flask_potion = "Potion",
            flask_pouch = "Pouch",
            flask_select = "Select a flask to spawn:",

            -- ====== Spells ======
            spell_select = "Select a spell to spawn:",
            spell_select_short = "Select a spell: ",

            -- ====== Perks ======
            perk_select = "Select a perk to spawn:",

            -- ====== Items / Spawnables ======
            item_select = "Select an item to spawn:",

            -- ====== Wands ======
            wand_select = "Select a wand to spawn:",
            wand_level_fmt = "Wand Level %d",
            wand_haxx = "Haxx",

            -- ====== Material selection ======
            material_select = "Select a material: ",

            -- ====== Fungi ======
            fungal_next_shift = "Next shift: ",
            fungal_next_shift1 = "Next shift+1: ",
            fungal_next_shift2 = "Next shift+2: ",
            fungal_from = "FROM: ",
            fungal_to = "TO: ",
            fungal_force = "[Force convert]",
            fungal_would_convert = "Would convert: %s -> %s",
            fungal_no_effect = "No effect (same material chosen as src and dest)",

            -- ====== Console ======
            console_close_host = "[Close console host]",
            console_open_host = "[Open console host]",
            console_open_new = "[Open new console]",
            console_separator = "---- Active Connections (click to close) ----",
            console_conn_format = "%s [in: %d, out: %d]",

            -- ====== Info Widgets ======
            widget_playtime = "Playtime",
            widget_visited = "Visited",
            widget_gold = "Gold",
            widget_hearts = "Hearts",
            widget_items = "Items",
            widget_shot = "Shot",
            widget_kicked = "Kicked",
            widget_kills = "Kills",
            widget_damage = "Damage taken",
            widget_frame = "Frame",
            widget_position = "Position",

            -- ====== Info widget display format ======
            widget_stat_fmt = "%s: %s",
            widget_frame_fmt = "Frame: %08d",
            widget_position_fmt = "X: %d, Y: %d",
            widget_alchemy_fmt = "%s: %s",

            -- ====== Widget panel ======
            widget_add_info = "Adding %s to info bar (minimize cheatgui to see)",

            -- ====== Extra buttons (menu) ======
            extra_edit_wands = "[edit wands everywhere]",
            extra_spell_refresh = "[spell refresh]",
            extra_full_heal = "[full heal]",
            extra_end_trip = "[end fungal trip]",
            extra_reset_timer = "[reset fungal shift timer]",
            extra_spawn_orbs = "[spawn orbs]",
            extra_open_console = "[open console]",

            -- ====== Tourist mode ======
            tourist_enable_fmt = "[enable %s]",
            tourist_disable_fmt = "[disable %s]",
            tourist_mode_name = "tourist mode",
            tourist_log = "Tourist mode: %s",

            -- ====== Log / print ======
            log_spawn = "Attempting to spawn %s",
            log_spawn_potion = "Attempting to spawn potion of %s",
            log_gui_error = "cheatgui err: %s",
            log_alchemy = "%s: %s",

            -- ====== Alchemy recipe labels ======
            alchemy_lc = "LC",
            alchemy_ap = "AP",

            -- ====== Settings ======
            settings_language = "Language:",
            lang_en = "English",
            lang_zh = "中文",

            -- ====== Title bar ======
            title_version = "cheatgui %s",
            title_no_keyboard_suffix = "S",
        },

        zh = {
            -- ====== Shared / General ======
            yes = "是",
            no = "否",
            none = "无",

            -- ====== Panel names ======
            panel_closed = "[+]",
            panel_wand_builder = "法杖构建",
            panel_teleport = "传送",
            panel_health = "生命",
            panel_gold = "金币",
            panel_spells = "法术",
            panel_perks = "天赋",
            panel_flasks = "药水",
            panel_wands = "法杖",
            panel_items = "物品",
            panel_widgets = "信息组件",
            panel_fungal = "真菌转换",
            panel_console = "控制台",
            panel_gui_grid_ref = "GUI坐标参考",
            panel_always_cast = "始终施法",
            panel_shift_material = "选择材料",
            panel_settings = "设置",

            -- ====== Breadcrumbs ======
            back = "< 返回",

            -- ====== Filter / Sort ======
            filter_label = "筛选:",
            filter_placeholder = "[Shift+输入以筛选]",
            alphabetize = "排序:",
            show_localized_names = "显示本地化名称:",

            -- ====== Page navigation ======
            page_prev_arrow = "<-",
            page_next_arrow = "->",

            -- ====== Wand Builder ======
            wb_shuffle = "乱序",
            wb_mana = "法力值",
            wb_mana_recharge = "法力回复",
            wb_slots = "槽位",
            wb_multicast = "多重施法",
            wb_reload = "充能时间",
            wb_delay = "施法延迟",
            wb_spread = "散射",
            wb_speed = "速度",
            wb_always_cast = "始终施法",
            wb_always_cast_n = "始终施法 (%d)",
            wb_none = "无",
            wb_reset_all = "[重置全部]",
            wb_spawn_wand = "[生成法杖]",

            -- ====== Teleport ======
            tp_x = "X",
            tp_y = "Y",
            tp_get_pos = "[获取当前位置]",
            tp_zero_pos = "[归零]",
            tp_teleport = "[传送]",
            tp_log_teleport = "正在尝试传送到 (%d, %d)",
            tp_separator = "---- 快速传送 ----",
            tp_quick_teleport_format = "%s (%d, %d)",

            -- ====== Health ======
            hp_hp = "生命值",
            hp_max_hp = "最大生命值",
            hp_get = "[获取当前生命]",
            hp_apply = "[应用生命变更]",
            hp_separator = "---- 快速生命操作 ----",
            hp_add_25 = "[增加 +25 最大生命]",
            hp_add_100 = "[增加 +100 最大生命]",

            -- ====== Gold ======
            gold_label = "金币",
            gold_get = "[获取当前金币]",
            gold_set = "[设置当前金币]",
            gold_separator = "---- 快速金币 ----",
            gold_add_100 = "[+100 金币]",
            gold_add_500 = "[+500 金币]",
            gold_add_2000 = "[+2000 金币]",

            -- ====== Flasks / Potions ======
            flask_quantity = "数量倍率:",
            flask_container = "容器:",
            flask_potion = "药水瓶",
            flask_pouch = "粉末袋",
            flask_select = "选择要生成的药水:",

            -- ====== Spells ======
            spell_select = "选择要生成的法术:",
            spell_select_short = "选择一个法术: ",

            -- ====== Perks ======
            perk_select = "选择要生成的天赋:",

            -- ====== Items / Spawnables ======
            item_select = "选择要生成的物品:",

            -- ====== Wands ======
            wand_select = "选择要生成的法杖:",
            wand_level_fmt = "法杖等级 %d",
            wand_haxx = "Haxx",

            -- ====== Material selection ======
            material_select = "选择一个材料: ",

            -- ====== Fungal ======
            fungal_next_shift = "下次转换: ",
            fungal_next_shift1 = "下次+1转换: ",
            fungal_next_shift2 = "下次+2转换: ",
            fungal_from = "从: ",
            fungal_to = "到: ",
            fungal_force = "[强制转换]",
            fungal_would_convert = "即将转换: %s -> %s",
            fungal_no_effect = "无效果（源和目标选择了相同材料）",

            -- ====== Console ======
            console_close_host = "[关闭控制台服务]",
            console_open_host = "[开启控制台服务]",
            console_open_new = "[打开新控制台]",
            console_separator = "---- 活跃连接（点击关闭）----",
            console_conn_format = "%s [接收: %d, 发送: %d]",

            -- ====== Info Widgets ======
            widget_playtime = "游戏时间",
            widget_visited = "探索区域",
            widget_gold = "金币",
            widget_hearts = "红心",
            widget_items = "物品",
            widget_shot = "射击",
            widget_kicked = "踢击",
            widget_kills = "击杀",
            widget_damage = "受到伤害",
            widget_frame = "帧数",
            widget_position = "坐标",

            -- ====== Info widget display format ======
            widget_stat_fmt = "%s: %s",
            widget_frame_fmt = "帧数: %08d",
            widget_position_fmt = "X: %d, Y: %d",
            widget_alchemy_fmt = "%s: %s",

            -- ====== Widget panel ======
            widget_add_info = "已添加 %s 到信息栏（最小化作弊菜单即可查看）",

            -- ====== Extra buttons (menu) ======
            extra_edit_wands = "[随处编辑法杖]",
            extra_spell_refresh = "[刷新法术]",
            extra_full_heal = "[完全治疗]",
            extra_end_trip = "[结束真菌致幻]",
            extra_reset_timer = "[重置真菌转换计时]",
            extra_spawn_orbs = "[生成宝珠]",
            extra_open_console = "[打开控制台]",

            -- ====== Tourist mode ======
            tourist_enable_fmt = "[启用 %s]",
            tourist_disable_fmt = "[禁用 %s]",
            tourist_mode_name = "观光模式",
            tourist_log = "观光模式: %s",

            -- ====== Log / print ======
            log_spawn = "正在尝试生成 %s",
            log_spawn_potion = "正在尝试生成药水: %s",
            log_gui_error = "cheatgui 错误: %s",
            log_alchemy = "%s: %s",

            -- ====== Alchemy recipe labels ======
            alchemy_lc = "LC",
            alchemy_ap = "AP",

            -- ====== Title bar ======
            title_version = "cheatgui %s",
            title_no_keyboard_suffix = "S",

            -- ====== Settings ======
            settings_language = "语言:",
            lang_en = "English",
            lang_zh = "中文",
        },
    },
}

-- Retrieve a translated string by key.
-- Falls back to English if the current language is missing a key.
-- Returns the raw key as a last resort.
function _i18n.t(self, key)
    local translations = self.translations[self.language] or self.translations["en"]
    return translations[key] or (self.translations["en"] and self.translations["en"][key]) or key
end

-- Convenience: translated format string + arguments
-- Usage: _i18n:tf("log_spawn", "some_item")
function _i18n.tf(self, key, ...)
    return self:t(key):format(...)
end
