-- Reiter "Profile" (Spec 3.6): aktives Profil dieses Charakters waehlen; anlegen, kopieren, umbenennen, loeschen,
-- zuruecksetzen (beziehen sich auf das aktive Profil); Export in ein markiertes Feld zum Kopieren; Import mit
-- Zielname. Existiert das Ziel schon, wird es nur nach einer Rueckfrage mit sichtbarem Zielnamen ueberschrieben.
--
-- Sicherheit: Profilnamen und Import-Text sind Fremddaten. Sie erscheinen nur ueber Widgets.Plain in FontStrings,
-- Menues und Rueckfragen ("|" verdoppelt). Der Import-String wird ausschliesslich von Store.DecodeImport/
-- ImportProfile gelesen (eigener Parser, kein Code), nie ausgegeben. Fehlermeldungen kommen aus den Locales.
local _, ns = ...
local Store = ns.Store
local Config, W = ns.Config, ns.Widgets
local L = ns.L
local C = W.COLORS

local Profiles = {}
Config.Profiles = Profiles

local function setStatus(page, text, c)
    page.status:SetText(text or "")
    W.Color(page.status, c or C.muted)
end

--- Fehlercode des Store als Text in Client-Sprache (Argument entschaerft)
local function fail(page, code, arg)
    setStatus(page, (L[code or "IMPORT_CORRUPT"]):format(W.Plain(arg or "")), C.warn)
end
Profiles.Fail = fail

local function ok(page, text) setStatus(page, text, C.ok) end

local function active() return Store.GetActiveName() end

local function inputName(page) return page.name:GetText() or "" end

-- Aktionen -------------------------------------------------------------------------------------------
function Profiles.Activate(page, name)
    local res, code, arg = Store.SetActive(name)
    if not res then fail(page, code, arg) else ok(page, L.UI_PROFILE_ACTIVATED:format(W.Plain(name))) end
    Config.Refresh(true)
end

function Profiles.Create(page)
    local name, code, arg = Store.CreateProfile(inputName(page))
    if not name then return fail(page, code, arg) end
    Store.SetActive(name)
    page.name:SetText("")
    ok(page, L.UI_PROFILE_CREATED:format(W.Plain(name)))
    Config.Refresh(true)
end

function Profiles.Copy(page)
    local src = active()
    local name, code, arg = Store.CopyProfile(src, inputName(page))
    if not name then return fail(page, code, arg) end
    Store.SetActive(name)
    page.name:SetText("")
    ok(page, L.UI_PROFILE_COPIED:format(W.Plain(src), W.Plain(name)))
    Config.Refresh(true)
end

function Profiles.Rename(page)
    local old = active()
    local name, code, arg = Store.RenameProfile(old, inputName(page))
    if not name then return fail(page, code, arg) end
    page.name:SetText("")
    ok(page, L.UI_PROFILE_RENAMED:format(W.Plain(old), W.Plain(name)))
    Config.Refresh(true)
end

function Profiles.AskDelete(page)
    local name = active()
    if name == Store.DEFAULT then return fail(page, "PROFILE_DEFAULT_PROTECTED") end
    Config.Confirm(L.UI_DELETE_CONFIRM:format(W.Plain(name)), L.UI_PROFILE_DELETE, function()
        local res, code, arg = Store.DeleteProfile(name)
        if not res then return fail(page, code, arg) end
        ok(page, L.UI_PROFILE_DELETED:format(W.Plain(name)))
        Config.Refresh(true)
    end)
end

function Profiles.AskReset(page)
    local name = active()
    Config.Confirm(L.UI_RESET_CONFIRM:format(W.Plain(name)), L.UI_PROFILE_RESET, function()
        local res, code, arg = Store.ResetProfile(name)
        if not res then return fail(page, code, arg) end
        ok(page, L.UI_PROFILE_WAS_RESET:format(W.Plain(name)))
        Config.Refresh(true)
    end)
end

function Profiles.Export(page)
    local str, code, arg = Store.ExportProfile(active())
    if not str then
        page.exportText = ""
        page.export.edit:SetText("")
        return fail(page, code, arg)
    end
    page.exportText = str
    page.export.edit:SetText(str)
    page.export.edit:SetFocus()
    page.export.edit:HighlightText()
    ok(page, L.UI_EXPORT_DONE:format(W.Plain(active())))
end

--- Import: String pruefen, Zielname bestimmen; vorhandenes Ziel nur nach Rueckfrage mit Zielname ueberschreiben.
--- Danach ist das importierte Profil fuer diesen Charakter aktiv.
function Profiles.Import(page)
    local str = page.import.edit:GetText() or ""
    local res, code, detail = Store.DecodeImport(str)
    if not res then return fail(page, code, detail) end
    local raw = page.importName:GetText() or ""
    local target
    if raw:match("%S") then
        target = Store.ValidName(raw)
        if not target then return fail(page, "PROFILE_NAME_INVALID") end
    else
        target = res.name or "Import"
    end
    local function run(overwrite)
        local name, c2, d2 = Store.ImportProfile(str, target, overwrite)
        if not name then return fail(page, c2, d2) end
        Store.SetActive(name)
        page.import.edit:SetText("")
        page.importName:SetText("")
        ok(page, (overwrite and L.UI_IMPORT_REPLACED or L.UI_IMPORT_DONE):format(W.Plain(name)))
        Config.Refresh(true)
    end
    if Store.GetProfile(target) then
        Config.Confirm(L.UI_IMPORT_CONFIRM:format(W.Plain(target)), L.UI_IMPORT_OVERWRITE, function() run(true) end)
    else
        run(false)
    end
end

-- Aufbau ---------------------------------------------------------------------------------------------
Config.RegisterPage("profiles", {
    label = "UI_TAB_PROFILES",
    build = function(page)
        -- links: aktives Profil + Verwalten
        local h1 = W.Header(page, L.UI_PROFILE_ACTIVE, 350)
        h1:SetPoint("TOPLEFT", 0, -6)
        page.char = W.Text(page, "GameFontHighlightSmall", C.muted)
        page.char:SetPoint("TOPLEFT", 0, -30)
        page.char:SetWidth(350)
        page.profile = W.Dropdown(page, 240, function(v) Profiles.Activate(page, v) end)
        page.profile:SetPoint("TOPLEFT", 0, -50)

        local h2 = W.Header(page, L.UI_PROFILE_MANAGE, 350)
        h2:SetPoint("TOPLEFT", 0, -100)
        local nl = W.Text(page, "GameFontNormalSmall", C.muted)
        nl:SetPoint("TOPLEFT", 0, -124)
        nl:SetText(L.UI_PROFILE_NAME)
        page.name = W.Input(page, 240, Store.NAME_MAX)
        page.name:SetPoint("TOPLEFT", 0, -140)
        page.createBtn = W.Button(page, L.UI_PROFILE_CREATE, 112, function() Profiles.Create(page) end)
        page.createBtn:SetPoint("TOPLEFT", 0, -172)
        page.copyBtn = W.Button(page, L.UI_PROFILE_COPY, 112, function() Profiles.Copy(page) end)
        page.copyBtn:SetPoint("LEFT", page.createBtn, "RIGHT", 6, 0)
        page.renameBtn = W.Button(page, L.UI_PROFILE_RENAME, 112, function() Profiles.Rename(page) end)
        page.renameBtn:SetPoint("LEFT", page.copyBtn, "RIGHT", 6, 0)
        page.deleteBtn = W.Button(page, L.UI_PROFILE_DELETE, 112, function() Profiles.AskDelete(page) end)
        page.deleteBtn:SetPoint("TOPLEFT", 0, -200)
        page.resetBtn = W.Button(page, L.UI_PROFILE_RESET, 112, function() Profiles.AskReset(page) end)
        page.resetBtn:SetPoint("LEFT", page.deleteBtn, "RIGHT", 6, 0)
        local hint = W.Text(page, "GameFontHighlightSmall", C.muted)
        hint:SetPoint("TOPLEFT", 0, -234)
        hint:SetWidth(350)
        hint:SetText(L.UI_PROFILE_HINT)

        page.status = W.Text(page, "GameFontHighlight", C.muted)
        page.status:SetPoint("TOPLEFT", 0, -300)
        page.status:SetWidth(350)
        if page.status.SetWordWrap then page.status:SetWordWrap(true) end

        -- rechts: Export / Import
        local x = 380
        local h3 = W.Header(page, L.UI_EXPORT, 388)
        h3:SetPoint("TOPLEFT", x, -6)
        page.exportBtn = W.Button(page, L.UI_EXPORT_BUTTON, 150, function() Profiles.Export(page) end)
        page.exportBtn:SetPoint("TOPLEFT", x, -28)
        local eh = W.Text(page, "GameFontHighlightSmall", C.muted)
        eh:SetPoint("LEFT", page.exportBtn, "RIGHT", 10, 0)
        eh:SetText(L.UI_EXPORT_HINT)
        page.export = W.TextArea(page, 388, 90, Store.MAX_IMPORT)
        page.export:SetPoint("TOPLEFT", x, -56)
        page.exportText = ""
        -- nur zum Kopieren: Nutzer-Eingaben werden verworfen, der Text bleibt markiert
        page.export.edit:SetScript("OnTextChanged", function(self, userInput)
            if userInput and self:GetText() ~= page.exportText then
                self:SetText(page.exportText)
                self:HighlightText()
            end
        end)
        page.export.edit:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)

        local h4 = W.Header(page, L.UI_IMPORT, 388)
        h4:SetPoint("TOPLEFT", x, -170)
        page.import = W.TextArea(page, 388, 110, Store.MAX_IMPORT)
        page.import:SetPoint("TOPLEFT", x, -194)
        local il = W.Text(page, "GameFontNormalSmall", C.muted)
        il:SetPoint("TOPLEFT", x, -316)
        il:SetText(L.UI_IMPORT_NAME)
        page.importName = W.Input(page, 220, Store.NAME_MAX)
        page.importName:SetPoint("TOPLEFT", x, -332)
        page.importBtn = W.Button(page, L.UI_IMPORT_BUTTON, 150, function() Profiles.Import(page) end)
        page.importBtn:SetPoint("LEFT", page.importName, "RIGHT", 10, 0)
        local ih = W.Text(page, "GameFontHighlightSmall", C.muted)
        ih:SetPoint("TOPLEFT", x, -362)
        ih:SetWidth(388)
        ih:SetText(L.UI_IMPORT_HINT)
        Profiles.page = page
    end,
    refresh = function(page)
        local key = Store.CharKey()
        page.char:SetText(L.UI_PROFILE_CHAR:format(W.Plain(key or "?")))
        local opts = {}
        for _, name in ipairs(Store.ListProfiles()) do opts[#opts + 1] = { value = name, text = W.Plain(name) } end
        page.profile:SetOptions(opts)
        page.profile:SetValue(active())
        if active() == Store.DEFAULT then
            page.renameBtn:Disable(); page.deleteBtn:Disable()
        else
            page.renameBtn:Enable(); page.deleteBtn:Enable()
        end
    end,
})
