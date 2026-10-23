-- C/C++ の上乗せ設定。clangd 本体の設定は LazyVim の lang.clangd extra が持っている
-- （有効化は lazyvim.json）。ここは Visual Studio のソリューションを読ませるための道具だけ。
--
-- なぜ要るか: clangd は compile_commands.json が無いと「今開いているファイルの翻訳単位」しか
-- 解析できない。別の .cpp にある定義は参照検索に出ず、プロジェクト固有の include パスや
-- /D も効かない。MSBuild は compile_commands.json を出さない。
--
-- 今は lazymsbuild が作る（plugins/lazymsbuild.lua の :CompileCommands = lazymsbuild sync）。
-- DB は <リポジトリのルート>\compile_commands.json に置かれ、ビルドのたびに追従する。
--   本体の導入 = tools/Install-Lazymsbuild.ps1（install.ps1 が呼ぶ）
--   正本 = https://github.com/6r1ntry52o/lazymsbuild
-- このファイルに残っているのは次の 2 つだけ。
--   1. lazymsbuild が PATH に無い PC（移行期間の保険）: 従来の :CompileCommands。Microsoft の
--      抽出ツール（design-time 評価なのでビルド不要）を直接呼び、<ルート>\build\compile_commands.json
--      を作る（clangd はファイルの親ディレクトリとその build/ を順に探すので、置くだけで拾う）。
--        導入 = tools/Install-MsbuildExtractor.ps1・正本 = https://github.com/microsoft/msbuild-extractor-sample
--   2. lazymsbuild がある PC: 1 が作った古い build\compile_commands.json が残っていたら、消すか聞く
--      （DB が 2 つあると、clangd が古い方を読み続けることがある）。

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

---from から上へ、.sln（無ければ .vcxproj）を探す。.sln なら 2 つ目に true。
---@param from string
---@return string|nil, boolean
local function find_target(from)
  -- .sln を優先（ソリューション内の全プロジェクトを 1 つの DB にまとめられる）。無ければ .vcxproj。
  local sln = vim.fs.find(function(name)
    return name:match("%.slnx?$") ~= nil
  end, { path = from, upward = true, type = "file" })[1]
  if sln then
    return sln, true
  end
  return vim.fs.find(function(name)
    return name:match("%.vcxproj$") ~= nil
  end, { path = from, upward = true, type = "file" })[1], false
end

local function generate()
  local from = vim.fn.expand("%:p:h")
  if from == "" then
    from = assert(vim.uv.cwd())
  end
  local target, is_sln = find_target(from)
  local sln = is_sln and target or nil
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

-- 2. 古い build\compile_commands.json の片付け。「もう聞かない」と答えたパスはここに残す。
local keep_file = vim.fs.joinpath(vim.fn.stdpath("state"), "lazymsbuild-keep-old-db.json")
local asked = {}

---@return string[]
local function kept()
  local ok, lines = pcall(vim.fn.readfile, keep_file)
  local decoded, list = pcall(vim.json.decode, ok and table.concat(lines, "\n") or "")
  return decoded and type(list) == "table" and list or {}
end

local function same_path(a, b)
  return vim.fs.normalize(a):lower() == vim.fs.normalize(b):lower()
end

---file のソリューションに、1 が作った build\compile_commands.json が残っていれば、消すか聞く。
---lazymsbuild 自身の DB（output.path を build/ にした時）と、lazymsbuild の DB がまだ無い時は聞かない。
---@param file string
local function offer_cleanup(file)
  local sln, is_sln = find_target(vim.fs.dirname(file))
  if not (sln and is_sln) then
    return
  end
  local old = vim.fs.joinpath(vim.fs.dirname(sln), "build", "compile_commands.json")
  if asked[old:lower()] or not vim.uv.fs_stat(old) then
    return
  end
  asked[old:lower()] = true
  for _, path in ipairs(kept()) do
    if same_path(path, old) then
      return
    end
  end
  vim.system({ "lazymsbuild", "-C", vim.fs.dirname(sln), "--json", "path" }, { text = true }, function(res)
    local ok, info = pcall(vim.json.decode, res.stdout or "")
    vim.schedule(function()
      if res.code ~= 0 or not ok or type(info) ~= "table" or type(info.db_file) ~= "string" then
        return
      end
      if same_path(info.db_file, old) or not vim.uv.fs_stat(info.db_file) then
        return
      end
      vim.ui.select({ "消す", "今回は残す", "残す（もう聞かない）" }, {
        prompt = ("古い %s が残っている（lazymsbuild の DB は %s）。clangd が古い方を読むことがある"):format(old, info.db_file),
      }, function(choice)
        if choice == "消す" then
          local removed, err = os.remove(old)
          if removed then
            vim.notify("消した: " .. old)
          else
            vim.notify("消せなかった: " .. tostring(err), vim.log.levels.ERROR)
          end
        elseif choice == "残す（もう聞かない）" then
          local list = kept()
          table.insert(list, old)
          vim.fn.mkdir(vim.fs.dirname(keep_file), "p")
          vim.fn.writefile({ vim.json.encode(list) }, keep_file)
        end
      end)
    end)
  end)
end

return {
  {
    "p00f/clangd_extensions.nvim",
    optional = true,
    -- init は起動時に走る（プラグイン本体のロードとは別）＝C++ を開く前でもコマンドは使える
    init = function()
      if vim.fn.executable("lazymsbuild") == 1 then
        -- :CompileCommands は plugins/lazymsbuild.lua が定義する（lazymsbuild sync）
        vim.api.nvim_create_autocmd("FileType", {
          group = vim.api.nvim_create_augroup("dotfiles_old_compile_commands", { clear = true }),
          pattern = { "c", "cpp" },
          callback = function(event)
            local name = vim.api.nvim_buf_get_name(event.buf)
            if name ~= "" then
              offer_cleanup(name)
            end
          end,
        })
        return
      end
      vim.api.nvim_create_user_command("CompileCommands", generate, {
        desc = "VS のソリューション/プロジェクトから compile_commands.json を作る（lazymsbuild が無い時）",
      })
    end,
  },
}
