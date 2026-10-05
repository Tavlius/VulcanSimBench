-- SimBench: the copy window and the Character-panel button. WoW can't touch
-- the clipboard, so the string opens in a text box with everything selected:
-- press Ctrl+C, then paste it into the sim.
local _, ns = ...

local copyFrame, editBox, noteText

local function BuildCopyFrame()
  local f = CreateFrame("Frame", "VulcanSimBenchCopyFrame", UIParent,
    BackdropTemplateMixin and "BackdropTemplate" or nil)
  f:SetSize(520, 220)
  f:SetPoint("CENTER")
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  if f.SetBackdrop then
    f:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0, 0, 0, 0.9)
  end

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 12, -10)
  f.title = title

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -2, -2)

  local scroll = CreateFrame("ScrollFrame", "VulcanSimBenchCopyScroll", f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 12, -32)
  scroll:SetPoint("BOTTOMRIGHT", -30, 56)
  f.scroll = scroll

  local box = CreateFrame("EditBox", nil, scroll)
  box:SetMultiLine(true)
  box:SetMaxLetters(0)   -- no length cap (some templates default to 255)
  box:SetAutoFocus(true)
  box:SetFontObject(ChatFontNormal)
  box:SetWidth(470)
  box:SetScript("OnEscapePressed", function() f:Hide() end)
  -- Copy mode: typing would change the string and break its checksum, so any
  -- edit puts the original text back and reselects it.
  -- Paste mode (/simx verify): whatever is pasted is checked as it arrives.
  box:SetScript("OnTextChanged", function(self, userInput)
    if not userInput then return end
    if f.onPaste then
      f.onPaste(self:GetText())
    elseif f.text and self:GetText() ~= f.text then
      self:SetText(f.text)
      self:HighlightText()
    end
  end)
  box:SetScript("OnEditFocusGained", function(self) if not f.onPaste then self:HighlightText() end end)
  scroll:SetScrollChild(box)
  -- The box is only as tall as its text; a click anywhere in the scroll area
  -- puts the cursor back in it (matters for the empty paste box).
  scroll:EnableMouse(true)
  scroll:SetScript("OnMouseDown", function() box:SetFocus() end)

  local note = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  note:SetPoint("BOTTOMLEFT", 12, 10)
  note:SetPoint("BOTTOMRIGHT", -12, 10)
  note:SetJustifyH("LEFT")
  note:SetJustifyV("BOTTOM")

  -- The sim's web address.
  local simButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  simButton:SetSize(120, 20)
  simButton:SetPoint("TOPRIGHT", -30, -6)
  simButton:SetText("Where's the sim?")
  simButton:SetScript("OnClick", function() ns.ShowSimURL() end)
  f.simButton = simButton
  f.note = note

  if UISpecialFrames then table.insert(UISpecialFrames, "VulcanSimBenchCopyFrame") end
  copyFrame, editBox, noteText = f, box, note
end

local function SetNotes(notes, default)
  local n = notes and #notes or 0
  noteText:SetText(n > 0 and table.concat(notes, "\n") or default)
  -- Room for every note: measured when the client can (long notes wrap to
  -- three lines), otherwise about two lines each at this width.
  noteText:SetHeight(0)
  local measured = ns.num(ns.try(noteText.GetStringHeight, noteText))
  local noteHeight = math.max(math.max(1, n) * 26, measured and (measured + 6) or 0)
  noteText:SetHeight(noteHeight)
  copyFrame:SetHeight(140 + noteHeight)
  copyFrame.scroll:SetPoint("BOTTOMRIGHT", -30, 16 + noteHeight)
end
ns.SetBoxNotes = function(notes)
  ns.lastNotes = notes or {}
  if noteText then SetNotes(notes, "") end
end

-- The sim is a web page. WoW can't open a browser, so this shows the address,
-- ready to copy. Returns it.
ns.SIM_URL = "https://vulcanaddons.com/sim"
function ns.ShowSimURL()
  ns.ShowCopy(ns.SIM_URL, { "The Vulcan Sim's web address. Copy it (Ctrl+C) and open it in any web browser." })
  return ns.SIM_URL
end

-- Shows the string ready to copy, with notes under it. Returns the text.
function ns.ShowCopy(text, notes)
  if not copyFrame then BuildCopyFrame() end
  copyFrame.text, copyFrame.onPaste = text, nil
  copyFrame.title:SetText("SimBench  |cff888888(Ctrl+C or Cmd+C to copy, Esc to close)|r")
  ns.lastNotes = notes or {}
  editBox:SetText(text)
  editBox:HighlightText()
  copyFrame:Show()   -- before SetNotes, so the note text has a width to measure
  SetNotes(notes, "Paste it into the Your character box at vulcanaddons.com/sim. The button above shows the address.")
  editBox:SetFocus()
  return text
end

-- An empty box to paste into; onPaste(text) runs on each paste or edit.
-- (Chat input stops at 255 characters, far shorter than an export string.)
function ns.ShowPaste(onPaste, notes)
  if not copyFrame then BuildCopyFrame() end
  copyFrame.text, copyFrame.onPaste = nil, onPaste
  copyFrame.title:SetText("SimBench  |cff888888(Ctrl+V or Cmd+V to paste, Esc to close)|r")
  ns.lastNotes = notes or {}
  editBox:SetText("")
  copyFrame:Show()
  SetNotes(notes, "")
  editBox:SetFocus()
end

function ns.CopyFrame() return copyFrame end

-- A small "Sim" button on the Character panel, if the panel exists.
function ns.AddCharacterButton()
  if VulcanSimBenchCharDB and VulcanSimBenchCharDB.hideButton then return end
  local parent = _G.PaperDollFrame or _G.CharacterFrame
  if not parent or ns.charButton then return end
  local ok, b = pcall(CreateFrame, "Button", "VulcanSimBenchCharButton", parent, "UIPanelButtonTemplate")
  if not ok or not b then return end
  b:SetSize(48, 20)
  b:SetText("Sim")
  b:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -40, -40)
  b:SetScript("OnClick", function() ns.Export() end)
  b:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("SimBench")
    GameTooltip:AddLine("Copy your gear and talents for the damage sim.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  ns.charButton = b
end

-- /simx button: show or hide the Character-panel button (saved per character).
function ns.ToggleCharacterButton()
  VulcanSimBenchCharDB = VulcanSimBenchCharDB or {}
  VulcanSimBenchCharDB.hideButton = not VulcanSimBenchCharDB.hideButton
  if VulcanSimBenchCharDB.hideButton then
    if ns.charButton then ns.charButton:Hide() end
  elseif ns.charButton then
    ns.charButton:Show()
  else
    ns.AddCharacterButton()
  end
  -- Second value: whether there's a button at all (no Character panel, no button).
  return not VulcanSimBenchCharDB.hideButton, ns.charButton ~= nil
end
