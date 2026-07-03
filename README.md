![作弊菜单在 Noita 中的截图](/screenshot.jpg?raw=true)

# Noita Cheat GUI（作弊菜单）
一个基础的游戏内作弊菜单。注意：如果你只想查看炼金术配方而不想要其他作弊功能，[这里有专门的模组](https://github.com/probable-basilisk/alchemyrecipes)。

## 安装

你可以手动下载模组，或者将此 Git 仓库克隆到 Noita 的 `mods` 子目录中。

### （推荐：选择加入 Noita 的 Steam beta 分支）
Cheatgui 是针对 beta 分支开发的，基本上也只在 beta 分支上测试过。它*可能*也能在非 beta 版本上运行，但不保证。

### 手动下载

[下载 release .zip 文件](https://github.com/probable-basilisk/cheatgui/releases/download/v1.3.0/cheatgui_v1_3_0_beta.zip)，
解压到你的 `Noita/mods/` 目录中，将文件夹重命名为 `cheatgui`。

**重要**：安装目录的命名很重要——**本 README 文件的路径最终应该是 `Noita/mods/cheatgui/README.md`**。

### （或）克隆 Git 仓库

你可以直接通过 git clone 将此仓库克隆到 mods 目录：

```
cd {你的 Noita 安装目录}/mods/
git clone https://github.com/probable-basilisk/cheatgui.git
```

**重要**：你需要从 [release zip 文件](https://github.com/probable-basilisk/cheatgui/releases/download/v1.3.0/cheatgui_v1_3_0_beta.zip)中获取 `pollnet.dll` 二进制文件，该文件位于 `bin/pollnet.dll`。你应该将此文件复制到 `Noita/mods/cheatgui/bin/pollnet.dll`。

### 在 Noita 中启用模组

通过游戏内的暂停菜单启用 'cheatgui' 模组。

系统会提示你"该模组已请求额外权限"——详细信息请参见下一节"关于警告提示的说明"。

#### 关于警告提示的说明

Cheatgui 需要不安全访问权限以支持键盘输入和启用 Web 控制台。如果这些警告让你感到困扰，可以获取 Steam 创意工坊版本，但你将无法使用键盘输入过滤和 Web 控制台功能。

## 关于路径的说明

目前我将模组的所有文件放在全局 `data/hax/` 路径下，而不是模组专属路径中。一方面是因为我比较懒，另一方面也是因为我可能想要从其他项目中交叉加载这些文件。
