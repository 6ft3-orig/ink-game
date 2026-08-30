--[[
    Ink Game — AutoQTE + Auto (Gonggi / Biseokchigi) + Glass Bridge ESP
    Единый скрипт. БЕЗ GUI и БЕЗ живых RenderStepped/Heartbeat-коннектов
    (проверено: под этим executor'ом они вешают клиент). Вся работа —
    один task-цикл опросом (паттерн, который НЕ вешает).

    Горячие клавиши (переключатели, по умолчанию всё ВЫКЛ):
      F1 — AutoQTE   (кольцевой QTE TugOfWar/PingPong + HBGQTE «красный/зелёный свет»)
      F2 — Gonggi    (авто-нажатие комбинации в QTEScreen)
      F3 — Biseokchigi/FlyingStone (идеальный бросок — ЛКМ в зоне Perfect)
      F4 — Glass Bridge ESP (подсветка: зелёное = безопасно, красное = провал)
      F7 — печать статуса в консоль

    Значения детекта взяты из исходников игры:
      * QTE-окно: |GoalDot.Rotation − CrossHair.Rotation| в кольце ≤ 26° (жать Space)
      * HBGQTE: клавиша в PlayerGui.ImpactFrames.QTEHolder ... Info.Text
      * ESP: небезопасная панель = PrimaryPart с атрибутом exploitingisevil=true
]]

--// СЕРВИСЫ
local Players            = game:GetService("Players")
local UserInputService   = game:GetService("UserInputService")
local VirtualInputManager= game:GetService("VirtualInputManager")
local Workspace          = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

--// НАСТРОЙКИ
local STEP           = 1/60      -- частота опроса цикла (сек). Достаточно быстрая для QTE.
local INPUT_GAP      = 0.05      -- мин. промежуток между двумя нажатиями (антиспам, 50мс)
local QTE_WINDOW     = 26        -- градусы окна попадания (25 в хардкоре; берём безопасно ≤26)
local QTE_LEAD       = 2         -- упреждение по углу (жать чуть раньше центра, т.к. кольцо крутится)
local SLIDER_TOL     = 0.06      -- допуск попадания в центр слайдера FlyingStone (scale)
local ESP_REFRESH    = 0.5       -- как часто пересобирать список панелей моста (сек)

--// СОСТОЯНИЕ
local Toggles = { QTE=false, Gonggi=false, Fly=false, ESP=false }
local lastPressAt = 0
local running = true

--// УТИЛИТЫ ВВОДА (без live-коннектов)
local function now() return os.clock() end

local function canPress()
    return (now() - lastPressAt) >= INPUT_GAP
end

local function tapKey(keyCode)
    if not canPress() then return end
    lastPressAt = now()
    VirtualInputManager:SendKeyEvent(true,  keyCode, false, game)
    task.delay(0.03, function()
        VirtualInputManager:SendKeyEvent(false, keyCode, false, game)
    end)
end

local function tapKeyByName(name)
    local kc = Enum.KeyCode[name]
    if kc then tapKey(kc) end
end

local function clickMouse()
    if not canPress() then return end
    lastPressAt = now()
    VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true,  game, 0)
    task.delay(0.03, function()
        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0)
    end)
end

--// ХЕЛПЕРЫ GUI
local function playerGui()
    return LocalPlayer:FindFirstChild("PlayerGui")
end

-- безопасный обход детей (без GetDescendants в горячем пути)
local function child(inst, name)
    return inst and inst:FindFirstChild(name)
end

--========================================================================
-- 1) AUTO QTE — кольцевой (TugOfWar / PingPong)
--    Ищем любой активный Progress с CrossHair+GoalDot, попадание ≤26°.
--========================================================================
-- Пути известных кольцевых QTE (монтируются в PlayerGui при активации).
local RING_QTE_HINTS = {
    -- name-хинты ScreenGui/Frame, где лежит .Progress
    "QTEEvents", "QTEEventsREUSINGPingPong", "PingPong", "TugOfWar", "TugOfWarUIV2",
}

local function nameMatchesRing(n)
    n = n:lower()
    for _, h in ipairs(RING_QTE_HINTS) do
        if n:find(h:lower(), 1, true) then return true end
    end
    return false
end

-- Тяжёлые GUI, которые НЕ сканируем рекурсивно (во избежание фриза).
local HEAVY_GUI = {
    ShopGui=true, RobloxGui=true, PSPlusGui=true, DailyRefreshOdds=true,
    EmoteGui=true, ScheduledRewards=true, SettingsGui=true, Battlepass=true,
}

-- Находит активный Frame "Progress" c CrossHair и GoalDot.
-- Сначала по имени-хинту QTE; если не нашли — безопасный обход прочих GUI (пропуская тяжёлые).
local function scanGuiForProgress(gui)
    local prog = gui:FindFirstChild("Progress", true)
    if prog then
        local cross = child(prog, "CrossHair")
        local goal  = child(prog, "GoalDot")
        if cross and goal then return prog, cross, goal end
    end
end

local function findRingProgress()
    local pg = playerGui()
    if not pg then return end
    -- 1) приоритет — GUI с именем-хинтом
    for _, gui in ipairs(pg:GetChildren()) do
        if gui:IsA("ScreenGui") and gui.Enabled and nameMatchesRing(gui.Name) then
            local p, c, g = scanGuiForProgress(gui)
            if p then return p, c, g end
        end
    end
    -- 2) fallback — прочие GUI, кроме заведомо тяжёлых
    for _, gui in ipairs(pg:GetChildren()) do
        if gui:IsA("ScreenGui") and gui.Enabled
           and not nameMatchesRing(gui.Name) and not HEAVY_GUI[gui.Name] then
            local p, c, g = scanGuiForProgress(gui)
            if p then return p, c, g end
        end
    end
end

local function ringDelta(goalRot, crossRot)
    return math.abs((goalRot - crossRot + 180) % 360 - 180)
end

local function stepRingQTE()
    local prog, cross, goal = findRingProgress()
    if not prog then return end
    -- Крутящийся CrossHair; жать Space когда в окне (с упреждением).
    local d = ringDelta(goal.Rotation, cross.Rotation)
    if d <= (QTE_WINDOW - QTE_LEAD) then
        tapKeyByName("Space")
    end
end

--========================================================================
-- 1b) AUTO QTE — HBGQTE («красный/зелёный свет»)
--     Кнопки в PlayerGui.ImpactFrames.QTEHolder, нужная клавиша в
--     ...QTEMain.Button.Inner.Info.Text (Q/Y/X/A/B ...).
--========================================================================
local function stepHBGQTE()
    local pg = playerGui()
    if not pg then return end
    local impact = child(pg, "ImpactFrames")
    if not impact then return end
    local holder = child(impact, "QTEHolder")
    if not holder then return end
    for _, node in ipairs(holder:GetChildren()) do
        -- каждая активная QTE-кнопка = клон с QTEMain.Button.Inner.Info
        local main = node:FindFirstChild("QTEMain", true)
        if main then
            local info = main:FindFirstChild("Info", true)
            if info and info:IsA("TextLabel") then
                local letter = info.Text
                if type(letter) == "string" and #letter >= 1 then
                    -- жмём требуемую букву (одиночная клавиша)
                    tapKeyByName(letter:sub(1,1):upper())
                end
            end
        end
    end
end

--========================================================================
-- 2) GONGGI — авто-нажатие комбинации.
--    Фаза QTE: OtherUIHolder.Gonggi.QTEScreen.MainBar.ButtonContents.Inner
--    (список кнопок по порядку). Читаем нужные клавиши и жмём.
--    NB: точный мап символ->клавиша уточняется по дампу с открытым комбо;
--    пока читаем Text/атрибут KeyCode с каждой кнопки Inner.
--========================================================================
local gonggiPressed = {}   -- чтобы не жать одну и ту же кнопку дважды

local function gonggiFindInner()
    local pg = playerGui()
    if not pg then return end
    local holder = child(pg, "OtherUIHolder")
    if not holder then return end
    local g = child(holder, "Gonggi")
    if not g then return end
    local qte = child(g, "QTEScreen")
    if not qte or (qte:IsA("GuiObject") and not qte.Visible) then return end
    local inner = qte:FindFirstChild("Inner", true)
    return inner
end

-- Пытается вытащить имя клавиши из кнопки последовательности.
local function gonggiKeyOf(btn)
    -- 1) атрибут KeyCode / Key
    local a = btn:GetAttribute("KeyCode") or btn:GetAttribute("Key")
    if type(a) == "string" and #a > 0 then return a end
    -- 2) текстовый label с цифрой/буквой
    local lbl = btn:FindFirstChildWhichIsA("TextLabel")
    if lbl and type(lbl.Text) == "string" and #lbl.Text > 0 then
        local s = lbl.Text:match("%w")
        if s then return s end
    end
    -- 3) по имени элемента (YTriangle/RCircle/Square/GTriangle/BCircle -> клавиши)
    local nameMap = {
        YTriangle="Three", GTriangle="Four", RCircle="One", BCircle="Two", Square="One",
    }
    return nameMap[btn.Name]
end

local function stepGonggi()
    local inner = gonggiFindInner()
    if not inner then gonggiPressed = {} return end
    -- дети Inner = кнопки последовательности слева-направо (порядок = layout)
    for _, btn in ipairs(inner:GetChildren()) do
        if btn:IsA("GuiObject") and btn.Visible then
            local id = tostring(btn)
            if not gonggiPressed[id] then
                local key = gonggiKeyOf(btn)
                if key then
                    -- цифра или имя клавиши
                    local kc = Enum.KeyCode[key] or Enum.KeyCode[("%s"):format(key)]
                    if not kc and tonumber(key) then
                        -- цифра 1..4 -> Enum.KeyCode.One..Four
                        local names = {"One","Two","Three","Four","Five","Six","Seven","Eight","Nine"}
                        kc = Enum.KeyCode[names[tonumber(key)] or ""]
                    end
                    if kc then
                        tapKey(kc)
                        gonggiPressed[id] = true
                    end
                end
            end
        end
    end
end

--========================================================================
-- 3) BISEOKCHIGI / FLYINGSTONE — идеальный бросок.
--    OtherUIHolder.FlyingStone.SliderMinigame.MainBar:
--      PlayerMover (движущийся индикатор) должен попасть в HitBox/Perfect
--      (центр ~0.5). Кликаем ЛКМ когда индикатор в допуске.
--========================================================================
local flyClickedThisPhase = false

local function stepFly()
    local pg = playerGui()
    if not pg then flyClickedThisPhase=false return end
    local holder = child(pg, "OtherUIHolder")
    if not holder then flyClickedThisPhase=false return end
    local fs = child(holder, "FlyingStone")
    if not (fs and fs:IsA("GuiObject") and fs.Visible) then flyClickedThisPhase=false return end
    local slider = child(fs, "SliderMinigame")
    if not (slider and slider.Visible) then flyClickedThisPhase=false return end
    local bar = child(slider, "MainBar")
    if not bar then return end
    local mover = child(bar, "PlayerMover")
    local hitbox = child(bar, "HitBox")
    if not (mover and hitbox) then return end

    -- позиция индикатора по X (scale) и центр/полуширина HitBox
    local moverX = mover.Position.X.Scale
    local hbCenter = hitbox.Position.X.Scale        -- обычно 0.5
    local hbHalf   = (hitbox.Size.X.Scale * 0.5)    -- полуширина зоны
    local perfect  = child(hitbox, "Perfect")
    if perfect then
        -- если есть зона Perfect — сузим допуск до неё
        hbHalf = math.max(SLIDER_TOL, hitbox.Size.X.Scale * 0.5 * (perfect.Size.X.Scale))
    end

    if math.abs(moverX - hbCenter) <= math.max(SLIDER_TOL, hbHalf) then
        clickMouse()
    end
end

--========================================================================
-- 4) GLASS BRIDGE ESP — подсветка панелей.
--    Небезопасная (ломающаяся) панель: PrimaryPart:GetAttribute("exploitingisevil")==true
--    Безопасная: атрибута нет / false.
--    Панели: workspace.GlassBridge.GlassHolder -> ряды -> Model(PrimaryPart).
--========================================================================
local espHighlights = {}   -- [PrimaryPart] = Highlight
local espLastRefresh = 0

local function espClearAll()
    for part, hl in pairs(espHighlights) do
        if hl then hl:Destroy() end
    end
    espHighlights = {}
end

local COLOR_SAFE   = Color3.fromRGB(0, 255, 80)
local COLOR_UNSAFE = Color3.fromRGB(255, 40, 40)

local function espApply(part, unsafe)
    local hl = espHighlights[part]
    if not hl or not hl.Parent then
        hl = Instance.new("Highlight")
        hl.Name = "InkESP"
        hl.FillTransparency = 0.5
        hl.OutlineTransparency = 0
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hl.Adornee = part.Parent      -- подсветить всю модель панели
        hl.Parent = part
        espHighlights[part] = hl
    end
    local c = unsafe and COLOR_UNSAFE or COLOR_SAFE
    hl.FillColor = c
    hl.OutlineColor = c
end

local function stepESP()
    -- периодически (не каждый тик) пересобираем — панели статичны в раунде
    if (now() - espLastRefresh) < ESP_REFRESH then return end
    espLastRefresh = now()

    local gb = child(Workspace, "GlassBridge")
    local holder = gb and child(gb, "GlassHolder")
    if not holder then espClearAll() return end

    local seen = {}
    for _, row in ipairs(holder:GetChildren()) do
        for _, model in ipairs(row:GetChildren()) do
            if model:IsA("Model") and model.PrimaryPart then
                local pp = model.PrimaryPart
                local unsafe = pp:GetAttribute("exploitingisevil") == true
                espApply(pp, unsafe)
                seen[pp] = true
            end
        end
    end
    -- убрать подсветку с исчезнувших панелей
    for part, hl in pairs(espHighlights) do
        if not seen[part] then
            if hl then hl:Destroy() end
            espHighlights[part] = nil
        end
    end
end

--========================================================================
-- ГЛАВНЫЙ ЦИКЛ (task, без live-коннектов)
--========================================================================
local function statusLine()
    return ("[InkAuto] QTE=%s Gonggi=%s Fly=%s ESP=%s")
        :format(tostring(Toggles.QTE), tostring(Toggles.Gonggi),
                tostring(Toggles.Fly), tostring(Toggles.ESP))
end

-- Тумблеры опросом IsKeyDown с антидребезгом (без InputBegan-коннекта).
local keyHeld = {}
local function edge(keyName)
    local down = UserInputService:IsKeyDown(Enum.KeyCode[keyName])
    local was = keyHeld[keyName]
    keyHeld[keyName] = down
    return down and not was     -- true только в момент нажатия (front edge)
end

task.spawn(function()
    print(statusLine() .. "  (F1 QTE | F2 Gonggi | F3 Fly | F4 ESP | F7 статус)")
    while running do
        -- тумблеры
        if edge("F1") then Toggles.QTE    = not Toggles.QTE    print(statusLine()) end
        if edge("F2") then Toggles.Gonggi = not Toggles.Gonggi print(statusLine()) end
        if edge("F3") then Toggles.Fly    = not Toggles.Fly    print(statusLine()) end
        if edge("F4") then
            Toggles.ESP = not Toggles.ESP
            if not Toggles.ESP then espClearAll() end
            print(statusLine())
        end
        if edge("F7") then print(statusLine()) end

        -- фичи (каждая в pcall, чтобы одна ошибка не рушила цикл)
        if Toggles.QTE    then pcall(stepRingQTE); pcall(stepHBGQTE) end
        if Toggles.Gonggi then pcall(stepGonggi) end
        if Toggles.Fly    then pcall(stepFly) end
        if Toggles.ESP    then pcall(stepESP) else if next(espHighlights) then espClearAll() end end

        task.wait(STEP)
    end
    espClearAll()
end)
