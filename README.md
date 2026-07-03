# Noita CheatGUI 中文分支 & 模组工具集

[English](README_EN.md) | 中文

---

一个 Noita 模组工具集合，包含 CheatGUI 中文分支模组、三个独立解锁脚本，以及 Noita 组件/Lua API 参考文档。

## 项目内容

| 文件/目录 | 说明 |
|-----------|------|
| `component_documentation.txt` | Noita 实体组件系统完整文档，列出所有可用组件的成员变量、类型、默认值和描述。 |
| `lua_api_documentation.txt` | Noita Lua 模组 API 参考文档（API 版本 12），所有 C++ 导出函数列表。 |
| `dextrome_unlock_enemies.lua` | 一键解锁**全部 400+ 种敌人**图鉴进度的独立脚本。 |
| `dextrome_unlock_perks_picked.lua` | 一键解锁**全部约 107 种天赋**图鉴进度的独立脚本。 |
| `dextrome_unlock_spells_used.lua` | 一键解锁**全部约 460 种法术**图鉴进度的独立脚本。 |
| `noita-cheatgui/` | CheatGUI 作弊菜单模组 —— 中文分支 v1.6.0（见下方详述）。 |

## 目录结构

```
noita-cheatgui/
├── .gitignore
├── LICENSE                        # MIT 许可协议
├── README.md                      # 中文说明（本文件）
├── README_EN.md                   # 英文说明
├── mod.xml                        # 模组元数据
├── init.lua                       # 模组入口
├── screenshot.jpg                 # 截图
├── gen_spawnlist.py               # Python 生成脚本
├── data/hax/
│   ├── cheatgui.lua               # 主 GUI 文件（~1900 行）
│   ├── config.lua                 # 持久化配置系统
│   ├── console.lua                # WebSocket 远程控制台
│   ├── i18n.lua                   # 国际化支持（中/英）
│   ├── alchemy.lua                # 炼金术配方数据
│   ├── fungal.lua                 # 真菌转化数据
│   ├── gun_builder.lua            # 法杖构建器
│   ├── materials.lua              # 材料数据
│   ├── spawnables.lua             # 可生成实体列表
│   ├── special_spawnables.lua     # 特殊可生成实体
│   ├── superhackykb.lua           # 键盘输入支持
│   ├── utils.lua                  # 工具函数
│   ├── wand_empty.xml             # 空法杖模板
│   ├── wand_hax.lua / .xml        # 作弊法杖逻辑与模板
│   └── lib/
│       ├── json.lua               # JSON 解析库
│       └── pollnet.lua            # 网络轮询库（WebSocket）
└── www/                           # Web 控制台前端
    ├── index.html                 # Web 控制台页面
    ├── css/
    │   └── themes/                # dracula.css, eclipse.css
    ├── js/
    │   └── noitaconsole.js        # 控制台 JS 逻辑
    └── lib/
        ├── codemirror.js / .css   # 代码编辑器
        ├── jquery-2.2.2.min.js
        ├── xterm.js / .css        # 终端模拟器
        ├── xterm-addon-fit.js
        └── modes/lua/             # Lua 语法高亮
```

## CheatGUI 功能

`noita-cheatgui` 是一个功能全面的游戏内作弊/调试菜单模组，基于 [probable-basilisk/cheatgui](https://github.com/probable-basilisk/cheatgui) 的中文分支（v1.6.0）。

### 面板功能

| 面板 | 功能描述 |
|------|----------|
| **法杖构建** | 自定义创建法杖，配置法力值、槽位、多重施法、散射、施法延迟、充能时间、速度、是否乱序、始终施法等全部属性。 |
| **传送** | 自由传送到任意坐标，或一键跳转到预设地点（主线圣山、魔球、精粹、Boss、精粹吞噬者、独立区域等）。 |
| **生命** | 获取当前生命值，修改最大生命值，快速 +25/+100 最大生命。 |
| **金币** | 获取/设置金币数量，快速 +100/+500/+2000。 |
| **法术** | 生成任意法术到游戏世界，支持搜索与排序筛选。 |
| **天赋** | 生成任意天赋，支持搜索筛选。 |
| **药水** | 生成任意药水（瓶子/粉末袋），可调整数量倍率。 |
| **法杖** | 生成各等级法杖或作弊法杖（Haxx）。 |
| **物品** | 生成任意游戏物品和实体。 |
| **真菌转化** | 查看未来三次真菌转化结果，可选择材料强制触发转化。 |
| **信息组件** | 实时信息显示：游戏时间、探索区域、金币、红心、物品、射击/踢击次数、击杀、伤害、帧数、坐标。 |
| **控制台** | 启动/关闭 WebSocket 远程控制台（见下文）。 |
| **设置** | 切换语言（中文/English）、切换本地化名称显示。 |
| **其它** | 随处编辑法杖、刷新法术、完全治疗、结束真菌致幻、重置真菌计时、生成魔球、一键解锁全部进度、观光模式等。 |

### Web 远程控制台

- 内置 WebSocket 服务器（端口 **9777**）和 HTTP 服务器（端口 **8777**）
- 加载存档后，在浏览器打开 `http://localhost:8777` 即可连接
- 提供交互式 Lua REPL，支持 CodeMirror 语法高亮和 xterm.js 终端输出
- 使用 Token 认证机制，仅限 localhost 访问

### 炼金术配方

信息组件可显示当前所在位置的 LC（活性混合物）和 AP（炼金前体）配方，方便进行炼金术实验。

## 安装方法

1. 将整个 `noita-cheatgui` 文件夹复制到 Noita 的模组目录：
   ```
   <Steam>/steamapps/common/Noita/mods/noita-cheatgui/
   ```
2. 在游戏主菜单的「模组」选项中启用「**Cheatgui中文分支**」。
3. （可选）如需使用 Web 远程控制台，加载存档后在浏览器打开 `http://localhost:8777`。

> **关于权限警告**：CheatGUI 需要 `request_no_api_restrictions="1"` 权限以支持键盘输入过滤和 Web 控制台功能。这是正常的，可以安全启用。

## 持久化配置项

CheatGUI 使用 Noita 的 `GlobalsSetValue` / `GlobalsGetValue` API 保存用户偏好设置，配置在游戏重启后仍然生效。配置定义在 `data/hax/config.lua` 中。

### 配置项说明

| 配置键 | 存储键（Globals） | 类型 | 默认值 | 说明 |
|--------|-------------------|------|--------|------|
| `language` | `cheatgui.config.language` | `string` | `"zh"` | 界面语言。`"zh"` 为中文，`"en"` 为英文。在设置的「语言」选项中修改。 |
| `show_localized_names` | `cheatgui.config.show_localized_names` | `boolean` | `true` | 是否显示游戏本地化名称。`true` 时法术/天赋/物品等列表项会显示游戏翻译后的名称；`false` 时显示原始内部 ID。在设置的「显示本地化名称」选项中修改。 |

### 实现原理

```lua
-- 存储：所有值以字符串形式通过 GlobalsSetValue 持久化
_config:set("language", "zh")
-- → GlobalsSetValue("cheatgui.config.language", "zh")

-- 读取：从 Globals 读取并自动转换回原始类型
local lang = _config:get("language")
-- → GlobalsGetValue("cheatgui.config.language") → "zh"

-- 启动时加载流程（cheatgui.lua 中）：
_config:load()                -- 从 Globals 加载所有配置
_i18n.language = _config:get("language")  -- 应用语言设置
```

- **命名空间前缀**：`cheatgui.config.` —— 避免与其他模组的 Globals 键冲突
- **类型转换**：读取时根据默认值类型自动将字符串转换回 `boolean`/`number`/`string`
- **延迟加载**：`_config:load()` 首次调用后缓存到 `_config.values`，后续读写直接操作内存
- **即时保存**：`_config:set()` 同时写入内存和 Globals，确保立即持久化

### 如何扩展

如需添加新的持久化配置项，只需两步：

```lua
-- 1. 在 config.lua 的 defaults 表中添加默认值
_config.defaults.my_new_option = "default_value"

-- 2. 在 cheatgui.lua 中
_config:load()
local val = _config:get("my_new_option")
-- 用户修改时：
_config:set("my_new_option", new_value)
```


## 许可协议

CheatGUI：MIT License。详见 `noita-cheatgui/LICENSE`。

---

*Noita 模组 API 参考请查看本仓库中的 `component_documentation.txt` 和 `lua_api_documentation.txt`。*
