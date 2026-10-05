-- C/C++ の上乗せ設定。clangd 本体の設定は LazyVim の lang.clangd extra が持っている
-- （有効化は lazyvim.json）。ここは Visual Studio のソリューションを読ませるための道具だけ。
--
-- なぜ要るか: clangd は compile_commands.json が無いと「今開いているファイルの翻訳単位」しか
-- 解析できない。別の .cpp にある定義は参照検索に出ず、プロジェクト固有の include パスや
-- /D も効かない。MSBuild は compile_commands.json を出さないので、Microsoft の抽出ツール
-- （design-time 評価なのでビルド不要）を呼んで作る。
--   本体の導入 = tools/Install-MsbuildExtractor.ps1（SHA256 検証つき）
--   正本 = https://github.com/microsoft/msbuild-extractor-sample
--
-- 出力先は <ルート>\build\compile_commands.json。clangd は編集中のファイルの親ディレクトリと
-- その build/ を順に探すので、置くだけで拾う（置き場所を設定しなくてよい）。

---ツール本体を探す。順番は Microsoft のスキルと同じ: PATH → <root>\.tools → %LOCALAPPDATA%。
---会社PCでは .tools\ に置く運用でも同じコマンドが動くように、3 か所見る。
---@param root string
---@return string|nil
local function find_extractor(root)
  local on_path = vim.fn.exepath("msbuild-extractor-sample")
  if on_path ~= "" then
    return on_path
  end
  for _, p in ipairs({
    vim.fs.joinpath(root, ".tools", "msbuild-extractor-sample.exe"),
    vim.fs.joinpath(vim.uv.os_getenv("LOCALAPPDATA") or "", "msbuild-extractor", "msbuild-extractor-sample.exe"),
  }) do
    if vim.uv.fs_stat(p) then
      return p
    end
  end
end

---.sln の SolutionConfigurationPlatforms の先頭を既定の構成として読む。
---Debug|x64 の決め打ちは「違う構成のフラグ」を掴む原因になる（Microsoft のスキルの注意）。
local function sln_default_config(sln)
  local in_section = false
  for line in io.lines(sln) do
    if line:find("GlobalSection(SolutionConfigurationPlatforms)", 1, true) then
      in_section = true
    elseif in_section then
      if line:find("EndGlobalSection", 1, true) then
        break
      end
      local cfg, plat = line:match("^%s*(.-)|(.-)%s*=")
      if cfg and plat and cfg ~= "" then
        return vim.trim(cfg), vim.trim(plat)
      end
    end
  end
end

---.vcxproj 単体のときは ProjectConfigurations の先頭。
local function vcxproj_default_config(proj)
  for line in io.lines(proj) do
    local cfg, plat = line:match('<ProjectConfiguration Include="(.-)|(.-)"')
    if cfg and plat then
      return cfg, plat
    end
  end
end

local function generate()
  local from = vim.fn.expand("%:p:h")
  if from == "" then
    from = assert(vim.uv.cwd())
  end
  -- .sln を優先（ソリューション内の全プロジェクトを 1 つの DB にまとめられる）。無ければ .vcxproj。
  local sln = vim.fs.find(function(name)
    return name:match("%.slnx?$") ~= nil
  end, { path = from, upward = true, type = "file" })[1]
  local target = sln
    or vim.fs.find(function(name)
      return name:match("%.vcxproj$") ~= nil
    end, { path = from, upward = true, type = "file" })[1]
  if not target then
    vim.notify("上の階層に .sln / .vcxproj が見つかりません", vim.log.levels.ERROR)
    return
  end

  local root = vim.fs.dirname(target)
  local exe = find_extractor(root)
  if not exe then
    vim.notify("msbuild-extractor-sample が無い（dotfiles の tools/Install-MsbuildExtractor.ps1 で入れる）", vim.log.levels.ERROR)
    return
  end

  local out = vim.fs.joinpath(root, "build", "compile_commands.json")
  vim.fn.mkdir(vim.fs.dirname(out), "p")

  local args
  local committed = vim.fs.joinpath(root, "msbuild-extractor.json")
  if vim.uv.fs_stat(committed) then
    -- リポが構成を宣言しているならそれに従う。-c/-a は渡さない（宣言を上書きしてしまう）。
    -- --config はパスを明示する（ツールは cwd からしか自動発見せず、黙って Debug|x64 に落ちる）。
    args = { exe, "--config", committed, sln and "--solution" or "--project", target, "-o", out }
  else
    local cfg, plat = (sln and sln_default_config or vcxproj_default_config)(target)
    if not cfg then
      vim.notify("構成（Debug|x64 等）を読み取れませんでした: " .. target, vim.log.levels.ERROR)
      return
    end
    args = { exe, sln and "--solution" or "--project", target, "-c", cfg, "-a", plat, "-o", out }
  end

  vim.notify("compile_commands.json を作成中… " .. vim.fs.basename(target))
  vim.system(args, { cwd = root, text = true }, function(res)
    local msg = (res.stdout or "") .. (res.stderr or "")
    vim.schedule(function()
      if res.code ~= 0 or not vim.uv.fs_stat(out) then
        -- 実測の罠: ツールは self-contained exe で hostfxr.dll を自力で解決できず、
        -- VS の MSBuild も見つけられないと DllNotFoundException で落ちる。
        -- dotnet の hostfxr.dll を exe の隣に置くと通る（導入スクリプトがやる）。
        if msg:find("DllNotFound", 1, true) then
          msg = msg .. "\n→ hostfxr.dll が exe の隣に無い（tools/Install-MsbuildExtractor.ps1 で入れ直す）"
        end
        vim.notify("作成に失敗\n" .. vim.trim(msg):sub(-600), vim.log.levels.ERROR)
        return
      end
      -- ツールは "Wrote N entries to ..." を出す。警告（VS の MSBuild が見つからない旨）は
      -- 出力先が作れていれば無害なので、件数だけ見せる。
      local n = msg:match("Wrote (%d+) entries") or "?"
      vim.notify(("compile_commands.json: %s 件 → %s"):format(n, out))
      pcall(vim.cmd, "LspRestart clangd")
    end)
  end)
end

return {
  {
    "p00f/clangd_extensions.nvim",
    optional = true,
    -- init は起動時に走る（プラグイン本体のロードとは別）＝C++ を開く前でもコマンドは使える
    init = function()
      vim.api.nvim_create_user_command("CompileCommands", generate, {
        desc = "VS のソリューション/プロジェクトから compile_commands.json を作る",
      })
    end,
  },
}
