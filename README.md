# win-dev-bootstrap

在没有管理员权限的 Windows 机器上，把 **Git / Node / pnpm / gh** 找齐并接上 `PATH`。

一堆公司电脑的默认状态：Node 装了、Git 没装、用户目录不在 `PATH` 里、装个东西还要 IT 审批。这个仓库就干一件事 —— **找到它们在哪儿，把环境串起来，然后告诉你还差什么**。

## 它解决什么问题

```
PS> git --version
git : 无法将"git"项识别为 cmdlet、函数、脚本文件或可运行程序的名称。
```

明明 `C:\Program Files\Git\cmd\git.exe` 就在那儿，只是没进 `PATH`。或者用了免安装版 Git（解压即用），从来就没在 `PATH` 里过。

## 用法

```powershell
# 1) 看这台机器现在到底有什么（只读，不改任何东西）
.\scripts\check-env.ps1

# 2) 把找到的工具接进当前会话的 PATH
.\scripts\dev-env.ps1

# 3) 再验证一次
.\scripts\check-env.ps1
```

`dev-env.ps1` 只改**当前这个 PowerShell 窗口**的环境变量，不动注册表、不动系统设置、不需要管理员，关掉窗口就恢复原样。

已知工具装在奇怪位置时直接指定：

```powershell
.\scripts\dev-env.ps1 -GitDir 'D:\tools\PortableGit\cmd' -NodeDir 'D:\tools\node'
```

想让新开的窗口也自动生效，在 PowerShell profile 末尾加一行：

```powershell
. 'D:\path\to\win-dev-bootstrap\scripts\dev-env.ps1' -Quiet
```

## 它会找哪些位置

| 工具 | 查找顺序 |
|---|---|
| git | `-GitDir` 参数 → `tools\PortableGit\cmd` → `C:\Program Files\Git\cmd` → `C:\Program Files (x86)\Git\cmd` → `%LOCALAPPDATA%\Programs\Git\cmd` |
| node | `-NodeDir` 参数 → `C:\Program Files\nodejs` → `%LOCALAPPDATA%\Programs\nodejs` → 当前 PATH |
| pnpm | 当前 PATH → `%APPDATA%\npm` |
| gh | `C:\Program Files\GitHub CLI` → `%LOCALAPPDATA%\Programs\gh` |

找不到不会报错中断，会告诉你「缺哪个、去哪装」。

## 免管理员装 Git 的办法

官方有免安装的 PortableGit：从 [git-for-windows Releases](https://github.com/git-for-windows/git/releases) 下 `PortableGit-<version>-64-bit.7z.exe`，**双击解压**到 `tools\PortableGit\`（7z 自解压，不需要管理员）。之后 `dev-env.ps1` 会自动认出来。

Node 同理：官方 zip 包解压到 `tools\node\` 即可，`npm` 和 `npx` 都在里面。

## 输出示例

```
  tool    status  version            where
  ------  ------  -----------------  ----------------------------------------
  git     OK      git version 2.56.1 C:\Program Files\Git\cmd\git.exe
  node    OK      v24.21.0           C:\Program Files\nodejs\node.exe
  pnpm    OK      11.7.0             C:\Users\me\AppData\Roaming\npm\pnpm.cmd
  gh      MISSING -                  install: winget install GitHub.cli
```

## 注意

- `check-env.ps1` 默认**不做任何网络测试**（有些公司网络下 `Test-NetConnection` 会卡 30 秒）。需要时加 `-TestNetwork`，并自己指定主机：

  ```powershell
  .\scripts\check-env.ps1 -TestNetwork -HostName github.com
  ```

- 执行策略如果是 `Restricted`，用 `powershell -ExecutionPolicy Bypass -File .\scripts\dev-env.ps1` 绕过（仅对这次运行生效）。
- 脚本只读环境、只改当前进程的 `PATH`，不会安装任何东西。要装东西它会打印命令让你自己决定。

## License

MIT，见 [LICENSE](LICENSE)。
