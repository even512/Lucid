-- Reiter "Chat" (Spec 3.4/3.5): Glass-Optik an/aus, Nachrichten-Fade an/aus, Sichtbarkeitsdauer, Dauer des
-- Ausblendens, Verzoegerung der Optik; rechts "Lesbarkeit": Kontur (keine/duenn/dick) und Schatten der Chat-Schrift
-- (unabhaengig von Glass/Fade, modules/Chat/Font.lua). Alles ueber Glass.Set (geprueft wie beim Import), wirkt sofort.
local _, ns = ...
local Glass, Fader = ns.Glass, ns.Fader
local Config, W = ns.Config, ns.Widgets
local L = ns.L
local C = W.COLORS

local Chat = {}
Config.Chat = Chat

local function sec(v) return ("%g s"):format(v) end

local function setStatus(page, text, c)
    page.status:SetText(text or "")
    W.Color(page.status, c or C.muted)
end

local function setter(page, key)
    return function(v)
        local ok, code = Glass.Set(key, v)
        if not ok then
            setStatus(page, L[code or "CHAT_VALUE_INVALID"], C.warn)
        else
            setStatus(page, "")
        end
        Config.Refresh()
    end
end

Config.RegisterPage("chat", {
    label = "UI_TAB_CHAT",
    build = function(page)
        local head = W.Header(page, L.UI_CHAT_LOOK, 360)
        head:SetPoint("TOPLEFT", 0, -6)
        page.glass = W.Check(page, L.UI_CHAT_GLASS, setter(page, "glass"))
        page.glass:SetPoint("TOPLEFT", 0, -28)
        W.Tooltip(page.glass, function() return L.UI_CHAT_GLASS, L.UI_CHAT_GLASS_TIP end)
        page.delay = W.Slider(page, L.UI_CHAT_DELAY, 0, Fader.MAX_TIME, 0.5, 300, sec, setter(page, "delay"))
        page.delay:SetPoint("TOPLEFT", 4, -62)
        W.Tooltip(page.delay, function() return L.UI_CHAT_DELAY, L.UI_CHAT_DELAY_TIP end)

        local head2 = W.Header(page, L.UI_CHAT_MESSAGES, 360)
        head2:SetPoint("TOPLEFT", 0, -130)
        page.fade = W.Check(page, L.UI_CHAT_FADE, setter(page, "fade"))
        page.fade:SetPoint("TOPLEFT", 0, -152)
        W.Tooltip(page.fade, function() return L.UI_CHAT_FADE, L.UI_CHAT_FADE_TIP end)
        page.time = W.Slider(page, L.UI_CHAT_TIME, Glass.TIME_MIN, Glass.TIME_MAX, 1, 300, sec, setter(page, "time"))
        page.time:SetPoint("TOPLEFT", 4, -186)
        page.duration = W.Slider(page, L.UI_CHAT_DURATION, 0, Glass.FADE_DURATION_MAX, 0.5, 300, sec,
            setter(page, "fadeDuration"))
        page.duration:SetPoint("TOPLEFT", 4, -236)

        page.note = W.Text(page, "GameFontHighlightSmall", C.muted)
        page.note:SetPoint("TOPLEFT", 4, -290)
        page.note:SetWidth(520)
        page.note:SetText(L.UI_CHAT_NOTE)
        -- Lesbarkeit (rechte Spalte)
        local head3 = W.Header(page, L.UI_CHAT_CONTRAST, 340)
        head3:SetPoint("TOPLEFT", 420, -6)
        local outlineLabel = W.Text(page, "GameFontNormalSmall", C.muted)
        outlineLabel:SetPoint("TOPLEFT", 420, -32)
        outlineLabel:SetText(L.UI_CHAT_OUTLINE)
        page.outline = W.Dropdown(page, 160, setter(page, "outline"))
        page.outline:SetPoint("TOPLEFT", 420, -48)
        page.outline:SetOptions({
            { value = "none", text = L.CHAT_OUTLINE_none },
            { value = "thin", text = L.CHAT_OUTLINE_thin },
            { value = "thick", text = L.CHAT_OUTLINE_thick },
        })
        W.Tooltip(page.outline, function() return L.UI_CHAT_OUTLINE, L.UI_CHAT_OUTLINE_TIP end)
        page.shadow = W.Check(page, L.UI_CHAT_SHADOW, setter(page, "shadow"))
        page.shadow:SetPoint("TOPLEFT", 416, -80)
        W.Tooltip(page.shadow, function() return L.UI_CHAT_SHADOW, L.UI_CHAT_SHADOW_TIP end)

        page.status = W.Text(page, "GameFontHighlightSmall", C.muted)
        page.status:SetPoint("TOPLEFT", 4, -330)
        page.status:SetWidth(520)
        Chat.page = page
    end,
    refresh = function(page)
        local cfg = Glass.GetConfig()
        page.glass:SetValue(cfg.glass)
        page.fade:SetValue(cfg.fade)
        page.delay:SetValue(cfg.delay)
        page.time:SetValue(cfg.time)
        page.duration:SetValue(cfg.fadeDuration)
        page.outline:SetValue(cfg.outline)
        page.shadow:SetValue(cfg.shadow)
        page.delay:SetActive(cfg.glass)
        page.time:SetActive(cfg.fade)
        page.duration:SetActive(cfg.fade)
        if cfg.glass and not Glass.IsGlassActive() then setStatus(page, L.CHAT_NO_FRAMES, C.warn) end
    end,
})
